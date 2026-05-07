import {
  LIGHT_OFF_COLOR,
  LIGHT_RED_COLOR,
  LIGHT_GREEN_COLOR,
  LIGHT_GOLD_COLOR,
  LIGHT_WARNING_COLOR,
  seededRandom,
} from "./gacha_cinematic_shared.js";

export function spiralCoords(minRow, maxRow, minCol, maxCol) {
  const out = [];
  let top = minRow;
  let bottom = maxRow;
  let left = minCol;
  let right = maxCol;
  while (top <= bottom && left <= right) {
    for (let c = left; c <= right; c += 1) out.push([top, c]);
    top += 1;
    for (let r = top; r <= bottom; r += 1) out.push([r, right]);
    right -= 1;
    if (top <= bottom) {
      for (let c = right; c >= left; c -= 1) out.push([bottom, c]);
      bottom -= 1;
    }
    if (left <= right) {
      for (let r = bottom; r >= top; r -= 1) out.push([r, left]);
      left += 1;
    }
  }
  return out;
}

function gridBounds(raceLights) {
  if (!raceLights.length) return null;
  const rows = raceLights.map((l) => l.row);
  const cols = raceLights.map((l) => l.col);
  return {
    minRow: Math.min(...rows),
    maxRow: Math.max(...rows),
    minCol: Math.min(...cols),
    maxCol: Math.max(...cols),
  };
}

export function buildRaceLightsTimeline(gsap, ctx, highestRarity, stale) {
  const tl = gsap.timeline();
  const strategy = Math.min(3, Math.max(1, highestRarity));
  const lights = () => ctx.getRaceLights();
  const seqId = () => ctx.getSequenceId();
  const results = () => ctx.getResults();
  const { setRaceLightState, setAllRaceLightsOff } = ctx;

  if (!lights().length) {
    tl.to({}, { duration: 0.38 });
    return tl;
  }

  const spiralOrder = () => {
    const bounds = gridBounds(lights());
    if (!bounds) return [];
    return spiralCoords(bounds.minRow, bounds.maxRow, bounds.minCol, bounds.maxCol);
  };

  if (strategy === 1) {
    tl.add(() => {
      if (stale()) return;
      setAllRaceLightsOff();
    });
    const cols = [...new Set(lights().map((l) => l.col))].sort((a, b) => a - b);
    cols.forEach((col) => {
      tl.add(() => {
        if (stale()) return;
        lights()
          .filter((l) => l.col === col)
          .forEach((light) => setRaceLightState(light, LIGHT_RED_COLOR, 0.75));
      });
      tl.to({}, { duration: 0.29 });
    });
    tl.to({}, { duration: 0.26 });
    tl.add(() => {
      if (stale()) return;
      lights().forEach((light) => setRaceLightState(light, LIGHT_GREEN_COLOR, 1.05));
    });
    tl.to({}, { duration: 0.42 });
    return tl;
  }

  if (strategy === 2) {
    tl.add(() => {
      if (stale()) return;
      setAllRaceLightsOff();
    });
    let order = spiralOrder();
    if (seqId() % 2 === 1) order = [...order].reverse();
    order.forEach(([row, col]) => {
      tl.add(() => {
        if (stale()) return;
        const target = lights().find((l) => l.row === row && l.col === col);
        if (target) setRaceLightState(target, LIGHT_RED_COLOR, 0.86);
      });
      tl.to({}, { duration: 0.11 });
    });
    tl.to({}, { duration: 0.1 });
    tl.add(() => {
      if (stale()) return;
      lights().forEach((light) => setRaceLightState(light, LIGHT_GREEN_COLOR, 1.06));
    });
    tl.to({}, { duration: 0.28 });
    return tl;
  }

  const rand = seededRandom((seqId() + 1) * 1337 + results().length * 17);
  const order = [...lights()]
    .map((l, idx) => ({ l, idx, r: rand() }))
    .sort((a, b) => a.r - b.r)
    .map((x) => x.l);

  tl.add(() => {
    if (stale()) return;
    setAllRaceLightsOff();
  });

  order.forEach((light, i) => {
    tl.add(() => {
      if (stale()) return;
      const crashTone = rand() > 0.55 ? LIGHT_RED_COLOR : LIGHT_WARNING_COLOR;
      setRaceLightState(light, crashTone, 0.9 + rand() * 0.35);
      if (i > 1 && i % 3 === 0) {
        const pulseLight = order[Math.floor(rand() * i)];
        setRaceLightState(pulseLight, LIGHT_RED_COLOR, 0.45);
      }
    });
    tl.to({}, { duration: (110 + Math.floor(rand() * 70)) / 1000 });
  });

  for (let pass = 0; pass < 6; pass += 1) {
    tl.add(() => {
      if (stale()) return;
      const chaotic = order.filter((_l, idx) => (idx + pass) % 2 === 0);
      chaotic.forEach((l) =>
        setRaceLightState(l, pass % 2 === 0 ? LIGHT_WARNING_COLOR : LIGHT_RED_COLOR, 1.12),
      );
      const rev = order.filter((_l, idx) => (idx + pass) % 2 !== 0);
      rev.forEach((l) =>
        setRaceLightState(l, pass % 2 === 0 ? LIGHT_RED_COLOR : LIGHT_WARNING_COLOR, 0.78),
      );
    });
    tl.to({}, { duration: 0.13 });
  }

  tl.to({}, { duration: 1.12 });
  tl.add(() => {
    if (stale()) return;
    order.forEach((l) => setRaceLightState(l, LIGHT_OFF_COLOR, 0.06));
  });
  tl.to({}, { duration: 0.12 });
  tl.add(() => {
    if (stale()) return;
    order.forEach((l) => setRaceLightState(l, LIGHT_GOLD_COLOR, 1.2));
  });
  tl.to({}, { duration: 0.62 });
  return tl;
}
