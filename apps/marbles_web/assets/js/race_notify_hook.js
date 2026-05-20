const RaceNotify = {
  mounted() {
    if ("Notification" in window && Notification.permission === "default") {
      Notification.requestPermission().catch(() => {});
    }

    this.handleEvent("race:notify", ({ race_id }) => {
      if (!race_id) return;

      const url = "/race/" + race_id;

      if (
        "Notification" in window &&
        Notification.permission === "granted" &&
        document.visibilityState !== "visible"
      ) {
        const n = new Notification("Your race is starting!", {
          body: "Tap to watch your squad race live.",
          tag: "race-" + race_id,
        });
        n.onclick = () => {
          window.focus();
          window.location.href = url;
          n.close();
        };
      }
    });
  },
};

export default RaceNotify;
