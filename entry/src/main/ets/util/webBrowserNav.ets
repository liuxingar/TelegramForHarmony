import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { normalizeExternalUrl, openUrl } from './openUrl';

// The URL the in-app browser should load for a tapped link: http/https URLs
// pass through, bare web addresses get an https:// scheme, and every other
// scheme ('' included) returns '' so callers fall back to the system handler.
export function webBrowserTarget(url: string): string {
  const target = normalizeExternalUrl(url);
  if (target === '') { return ''; }
  const lower = target.toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://') ? target : '';
}

// Open a tapped content link: web pages go to the in-app browser page, other
// schemes (tel:, mailto:, geo:, …) keep their system-app routing via openUrl.
export function openWebUrl(
  context: common.UIAbilityContext,
  url: string,
  onFailed: () => void = (): void => {}
): void {
  const target = webBrowserTarget(url);
  if (target === '') {
    openUrl(context, url, onFailed);
    return;
  }
  const params: Record<string, Object> = { 'url': target };
  router.pushUrl({ url: 'pages/web/InAppBrowserPage', params }).catch((e: Object): void => {
    console.error(`openWebUrl push failed for ${target}: ${JSON.stringify(e)}`);
    // The in-app page failing must never eat the tap — degrade to the browser.
    openUrl(context, target, onFailed);
  });
}
