import { DiscordSDK, attemptRemap, patchUrlMappings } from "@discord/embedded-app-sdk";

const oauthScope = ["identify"];
const attemptedKey = "discord_activity_auth_attempted";
const completedKey = "discord_activity_auth_completed";

const csrfToken = () => {
  const meta = document.querySelector("meta[name='csrf-token']");
  return meta ? meta.getAttribute("content") : "";
};

const normalizeError = (error) => {
  if (error && typeof error === "object" && "message" in error && typeof error.message === "string") {
    return error.message;
  }

  return "discord_activity_auth_failed";
};

const runningInIframe = () => {
  try {
    return window.self !== window.top;
  } catch {
    return true;
  }
};

const authorizeWithFallback = async (sdk, payload) => {
  try {
    return await sdk.commands.authorize({ ...payload, prompt: "none" });
  } catch {
    return sdk.commands.authorize({ ...payload, prompt: "consent" });
  }
};

const bootstrapNode = () => document.getElementById("discord-embedded-auth-bootstrap");

const fetchBootstrapConfig = () => {
  const el = bootstrapNode();
  if (!el || el.dataset.enabled !== "true") return null;

  const clientId = el.dataset.clientId;
  const authEndpoint = el.dataset.authEndpoint;
  const rawMappings = el.dataset.urlMappings || "[]";
  const urlMappings = (() => {
    try {
      const parsed = JSON.parse(rawMappings);
      if (!Array.isArray(parsed)) return [];

      return parsed
        .map((mapping) => {
          if (!mapping || typeof mapping !== "object") return null;

          const prefixRaw = typeof mapping.prefix === "string" ? mapping.prefix.trim() : "";
          const targetRaw = typeof mapping.target === "string" ? mapping.target.trim() : "";
          if (!prefixRaw || !targetRaw) return null;

          const prefix = prefixRaw.startsWith("/") ? prefixRaw : `/${prefixRaw}`;
          const target = targetRaw.replace(/^https?:\/\//, "").replace(/^\/+/, "");

          return { prefix, target };
        })
        .filter(Boolean);
    } catch {
      return [];
    }
  })();

  if (!clientId || !authEndpoint) return null;

  return { clientId, authEndpoint, urlMappings };
};

const shouldSkipAuth = () => {
  if (!runningInIframe()) return true;
  if (window.location.pathname.startsWith("/auth/")) return true;
  if (window.location.pathname.startsWith("/api/")) return true;
  return false;
};

const applyUrlMappings = (mappings) => {
  if (!Array.isArray(mappings) || mappings.length === 0) return;

  patchUrlMappings(mappings, {
    patchSrcAttributes: true,
  });
};

const remapUrl = (url, mappings) => {
  if (!url || typeof url !== "string") return url;
  if (!Array.isArray(mappings) || mappings.length === 0) return url;

  try {
    const remapped = attemptRemap({ url: new URL(url, window.location.href), mappings });
    return remapped.toString();
  } catch {
    return url;
  }
};

const markAttempted = () => sessionStorage.setItem(attemptedKey, "1");
const clearAttempted = () => sessionStorage.removeItem(attemptedKey);
const alreadyAttempted = () => sessionStorage.getItem(attemptedKey) === "1";
const markCompleted = () => sessionStorage.setItem(completedKey, "1");
const alreadyCompleted = () => sessionStorage.getItem(completedKey) === "1";

const exchangeCode = async (authEndpoint, code) => {
  const response = await fetch(authEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    credentials: "include",
    body: JSON.stringify({ code }),
  });

  const body = await response.json().catch(() => ({}));
  return { response, body };
};

const ensureUrlMappings = () => {
  if (shouldSkipAuth()) return;

  const config = fetchBootstrapConfig();
  if (!config) return;

  applyUrlMappings(config.urlMappings);
  window.__marblesDiscordRemapUrl = (url) => remapUrl(url, config.urlMappings);
};

const runDiscordEmbeddedAuth = async (liveSocket) => {
  if (shouldSkipAuth()) return;

  const config = fetchBootstrapConfig();
  if (!config) return;
  if (alreadyAttempted() || alreadyCompleted()) return;

  markAttempted();

  try {
    const sdk = new DiscordSDK(config.clientId);
    await sdk.ready();

    const authResult = await authorizeWithFallback(sdk, {
      client_id: config.clientId,
      response_type: "code",
      state: window.crypto?.randomUUID?.() || `${Date.now()}`,
      scope: oauthScope,
    });

    if (!authResult || typeof authResult.code !== "string" || authResult.code === "") {
      clearAttempted();
      return;
    }

    const { response, body } = await exchangeCode(config.authEndpoint, authResult.code);

    if (!response.ok || body.ok !== true || !body.user || typeof body.user.id !== "string") {
      clearAttempted();
      return;
    }

    markCompleted();
    if (liveSocket) {
      liveSocket.disconnect();
      liveSocket.connect();
    }
  } catch (error) {
    console.error("discord embedded auth failed", normalizeError(error));
    clearAttempted();
  }
};

const initializeDiscordUrlMappings = () => {
  ensureUrlMappings();
};

const bootstrapDiscordEmbeddedAuth = (liveSocket) => {
  runDiscordEmbeddedAuth(liveSocket);
  window.addEventListener("phx:page-loading-stop", () => runDiscordEmbeddedAuth(liveSocket));
};

export { bootstrapDiscordEmbeddedAuth, initializeDiscordUrlMappings };
