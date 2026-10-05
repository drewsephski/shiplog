import { createHash } from 'node:crypto';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';

export const PROMPT_VERSION = 'journal-synthesis-5';
export const kindSchema = z.enum(['feature', 'improvement', 'fix', 'release', 'learning']);
export const dayRequest = z.object({
  day: z.iso.date(),
  timeZone: z.string().max(100).refine(value => {
    try { Temporal.Now.zonedDateTimeISO(value); return true; } catch { return false; }
  }, 'Choose a valid IANA time zone'),
});
export type DayRequest = z.infer<typeof dayRequest>;
export function dayInterval({day, timeZone}: DayRequest) {
  const date = Temporal.PlainDate.from(day);
  const start = date.toZonedDateTime(timeZone);
  return {start: start.toInstant().toString(), end: date.add({days: 1}).toZonedDateTime(timeZone).toInstant().toString()};
}
export function localDay(timeZone: string, now = new Date()): string {
  return Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(timeZone).toPlainDate().toString();
}
export function localMinute(timeZone: string, now = new Date()): number {
  const time = Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(timeZone);
  return time.hour * 60 + time.minute;
}
export function reconciliationDays(since: Date, timeZone: string, now = new Date()): string[] {
  const today=Temporal.PlainDate.from(localDay(timeZone,now));
  const oldest=today.subtract({days:6});
  let cursor=Temporal.PlainDate.from(localDay(timeZone,since));
  if (Temporal.PlainDate.compare(cursor,oldest)<0) cursor=oldest;
  const days:string[]=[];
  while (Temporal.PlainDate.compare(cursor,today)<=0) { days.push(cursor.toString());cursor=cursor.add({days:1}); }
  return days;
}
export const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export function evidenceID(repositoryID: string, kind: string, externalID: string) {
  return ['github', repositoryID, kind, externalID].map(encodeURIComponent).join(':');
}
export const evidenceSchema = z.object({
  id: z.string(), repositoryID: z.string(), externalID: z.string(),
  kind: z.enum(['commit', 'pullRequest', 'issue']), title: z.string().max(1000),
  body: z.string().max(4000), occurredAt: z.iso.datetime({offset:true}),
  url: z.url().startsWith('https://github.com/'), actorID: z.string(),
  attribution: z.enum(['author','committer','actor']).optional(),
  files: z.array(z.object({path:z.string(), additions:z.number(), deletions:z.number(), patch:z.string().max(2000)})).max(30),
});
export type ActivityEvidence = z.infer<typeof evidenceSchema>;
export interface ConnectedRepository {
  id: string; installationID: string; name: string; fullName: string; url: string;
  description: string; isPrivate: boolean; defaultBranch: string;
}
export interface RepoContext {
  repositoryID: string; description: string; languages: string[];
  topLevelFiles: string[]; documents: {path:string; text:string}[];
}
export const generatedSchema = z.object({
  entries: z.array(z.object({
    repositoryID: z.string(), title: z.string().min(1).max(160), detail: z.string().max(4000),
    kind: kindSchema, confidence: z.number().min(0).max(1), evidenceIDs: z.array(z.string()).min(1).max(100),
  })).max(30),
  narrative: z.object({text:z.string().max(12000), evidenceIDs:z.array(z.string()).max(200)}),
});
export type SynthesisResult = z.infer<typeof generatedSchema>;
export interface SynthesisInput {
  day: string; contexts: RepoContext[]; evidence: ActivityEvidence[];
  existing: {id:string; title:string; detail:string; evidenceIDs:string[]; userEdited:boolean}[];
}
/** Reject invalid provenance before ANY result is persisted. Confidence is a model estimate. */
export function validateSynthesis(raw: unknown, input: SynthesisInput): SynthesisResult {
  const output = generatedSchema.parse(raw);
  const sources = new Map(input.evidence.map(item => [item.id, item]));
  const reserved = new Set(input.existing.filter(entry => entry.userEdited).flatMap(entry => entry.evidenceIDs));
  const used = new Set<string>();
  for (const entry of output.entries) {
    if (!input.contexts.some(repo => repo.repositoryID === entry.repositoryID)) throw new Error('Unknown repository');
    for (const id of entry.evidenceIDs) {
      if (sources.get(id)?.repositoryID !== entry.repositoryID) throw new Error('Unknown or cross-repository evidence');
      if (reserved.has(id)) throw new Error('Protected evidence reused');
      if (used.has(id)) throw new Error('Evidence assigned to multiple entries');
      used.add(id);
    }
  }
  for (const id of sources.keys()) {
    if (!used.has(id) && !reserved.has(id)) throw new Error('Evidence missing from the work log');
  }
  if (new Set(output.narrative.evidenceIDs).size !== output.narrative.evidenceIDs.length) throw new Error('Duplicate narrative evidence');
  for (const id of output.narrative.evidenceIDs) if (!used.has(id) && !(reserved.has(id) && sources.has(id))) throw new Error('Narrative cites work absent from entries');
  if (output.narrative.text.trim() && output.narrative.evidenceIDs.length === 0) throw new Error('Unsupported narrative');
  if (input.evidence.length > 0 && ((output.entries.length === 0 && reserved.size === 0) || !output.narrative.text.trim())) throw new Error('Empty synthesis');
  return output;
}
export function generationHash(input: SynthesisInput) {
  // Sort independent collections so transport order does not trigger regeneration.
  return hash(JSON.stringify({promptVersion:PROMPT_VERSION, ...input,
    evidence:[...input.evidence].sort((a,b) => a.id.localeCompare(b.id)),
    contexts:[...input.contexts].sort((a,b) => a.repositoryID.localeCompare(b.repositoryID)),
    existing:input.existing.filter(entry => entry.userEdited).sort((a,b) => a.id.localeCompare(b.id)),
  }, (_key, value: unknown) => value && typeof value === 'object' && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value).sort(([a],[b]) => a.localeCompare(b))) : value));
}
