const TERM = "202710";
const OUT = `${process.env.HOME}/Library/Application Support/classbar/schedule.json`;

const DAY_INDEX = {
  Monday: 0, Tuesday: 1, Wednesday: 2, Thursday: 3,
  Friday: 4, Saturday: 5, Sunday: 6,
};

function toClock(text) {
  const m = text.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const pm = /pm/i.test(m[3]);
  if (pm && h !== 12) h += 12;
  if (!pm && h === 12) h = 0;
  return `${String(h).padStart(2, "0")}:${m[2]}`;
}

await useOrCreateTaskSpace("fetch class schedule");

await gotoAndWait(
  "https://nubanner.neu.edu/StudentRegistrationSsb/ssb/registrationHistory/registrationHistory",
  { timeout: 60, settle: 10 },
);
await js(`(() => { const $ = window.jQuery;
  if ($) $('#lookupFilter').val('${TERM}').trigger('change'); })()`);
await wait(10);

const codeRows = await js(String.raw`(() => {
  const out = [];
  document.querySelectorAll('table tr').forEach(tr => {
    const c = [...tr.querySelectorAll('td')].map(td => td.innerText.trim());
    if (c.length > 2 && /^[A-Z]{2,5}\s?\d{4},\s*\w+$/.test(c[1]))
      out.push({ title: c[0], details: c[1] });
  });
  return out;
})()`);

const codeByTitle = new Map();
for (const r of codeRows) {
  const m = r.details.match(/^([A-Z]{2,5})\s?(\d{4})/);
  if (m) codeByTitle.set(r.title, `${m[1]} ${m[2]}`);
}

await click("#scheduleDetailsViewLink", { label: "schedule details" }).catch(() => {});
await wait(8);

const raw = String(await js(String.raw`document.body.innerText`));
const start = raw.indexOf("Class Schedule for");
if (start < 0) {
  cliLog("could not find the schedule section — is the term code right?");
  process.exit(1);
}

const lines = raw.slice(start).split("\n").map((l) => l.trim());
const parsed = [];
let cur = null;

for (const line of lines) {
  const header = line.match(/^(.+?)\s\|\s.+?\s(\d{4})\sSection\s(\w+)\s\|/);
  if (header) {
    if (cur && cur.days.length) parsed.push(cur);
    const title = header[1].trim();
    cur = {
      title,
      name: title,
      code: codeByTitle.get(title) || "",
      room: "",
      days: [],
      start: null,
      end: null,
    };
    continue;
  }
  if (!cur) continue;

  if (/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)(,|$)/.test(line)) {
    for (const d of line.split(",")) {
      const i = DAY_INDEX[d.trim()];
      if (i !== undefined && !cur.days.includes(i)) cur.days.push(i);
    }
    continue;
  }

  const t = line.match(/(\d{1,2}:\d{2}\s*[AP]M)\s*-\s*(\d{1,2}:\d{2}\s*[AP]M)/i);
  if (t) { cur.start = toClock(t[1]); cur.end = toClock(t[2]); }

  const w = line.match(/Building:\s*(.+?)\s+Room:\s*(\S+)/);
  if (w) {
    const b = w[1].trim();
    cur.room = /virtual|online/i.test(b) ? "Online" : `${b} ${w[2].trim()}`;
  }
}
if (cur && cur.days.length) parsed.push(cur);

const usable = parsed.filter((c) => c.start && c.end && c.days.length && c.code);
usable.sort((a, b) => a.start.localeCompare(b.start));

cliLog("CLASSBAR_JSON_START");
cliLog(JSON.stringify(usable.map((c) => ({
  name: c.name, code: c.code, room: c.room,
  days: c.days.sort((a, b) => a - b), start: c.start, end: c.end,
}))));
cliLog("CLASSBAR_JSON_END");
cliLog(`parsed ${usable.length} classes for term ${TERM}`);
