const BLOCKED_BY =
  /(?:blocked\s+by|depends\s+on|requires|needs|prereq(?:uisite)?|waits\s+on)\s+([\w.-]+\/[\w.-]+)?#(\d+)/gi;
const BLOCKING =
  /(?:blocks|unblocks|prerequisite\s+of)\s+([\w.-]+\/[\w.-]+)?#(\d+)/gi;

const collect = (re, kind, body, out) => {
  re.lastIndex = 0;
  let m;
  while ((m = re.exec(body)) !== null) {
    const n = parseInt(m[2], 10);
    if (!Number.isFinite(n)) continue;
    out.push({ kind, repo: m[1] || "", number: n });
  }
};

export const scanEdges = (body) => {
  if (typeof body !== "string" || body.length === 0) return [];
  const out = [];
  collect(BLOCKED_BY, "blockedBy", body, out);
  collect(BLOCKING, "blocking", body, out);
  return out;
};
