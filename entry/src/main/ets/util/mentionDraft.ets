// Draft-text helpers for mentioning a group member. Kept out of ChatPage so
// the string handling is unit-testable on its own.

// The text a mention inserts: '@username' when the member has a public one,
// otherwise the bare display name (matching the '@' suggestion panel — the
// send path is plain text, so a name-only mention carries no entity).
export function mentionToken(name: string, username: string): string {
  if (username !== '') {
    return `@${username}`;
  }
  return name.trim();
}

// Append `token` to `draft`, separated by a single space, always leaving a
// trailing space so the next word does not glue onto the mention. Repeating
// the mention that already trails the draft is a no-op.
export function appendMention(draft: string, token: string): string {
  if (token === '') {
    return draft;
  }
  if (alreadyTrailing(draft, token)) {
    return draft.endsWith(' ') ? draft : `${draft} `;
  }
  if (draft === '' || endsWithSpace(draft)) {
    return `${draft}${token} `;
  }
  return `${draft} ${token} `;
}

function endsWithSpace(text: string): boolean {
  const last = text.charAt(text.length - 1);
  return last.trim() === '';
}

// True when the draft's last non-space run is exactly this mention — guarded
// by a word boundary so '@alicia' does not swallow a fresh '@alice'.
function alreadyTrailing(draft: string, token: string): boolean {
  const trimmed = draft.replace(/\s+$/, '');
  if (!trimmed.endsWith(token)) {
    return false;
  }
  const head = trimmed.substring(0, trimmed.length - token.length);
  return head === '' || endsWithSpace(head);
}
