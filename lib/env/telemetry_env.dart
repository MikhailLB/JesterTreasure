// Jester Treasure — Microsoft Clarity project id.
//
// [FINGERPRINT] Never share a Clarity project across sibling apps —
// each of the 15 titles owns its own workspace so the dashboards stay
// legible and Play's static analysis can't cross-reference them.
//
// A single string constant lives here on purpose: the pipeline (facade
// + wiring) reads only this file, so a project migration is a
// one-line change.

const String kClarityWorkspaceId = 'xmex97879g';
