// Link cleaning shared by the notch and the node tests. No browser APIs.
(function (root, factory) {
  const api = factory();
  root.SV_URL = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  const TRACK_PREFIXES = ['utm_', 'pk_', 'mtm_', 'hsa_', 'ga_', '_hs', 'oly_', 'vero_', 'trk_', 'aff_', 'at_', 'sc_', 'wt_', 'pd_rd_', 'pf_rd_'];
  const TRACK_ANYWHERE = new Set([
    'fbclid', 'gclid', 'gclsrc', 'dclid', 'gbraid', 'wbraid', 'msclkid', 'yclid', 'ysclid', '_openstat', 'igshid', 'igsh',
    'mc_cid', 'mc_eid', 'mkt_tok', 'rb_clickid', 's_cid', 'wickedid', 'twclid', 'ttclid', 'li_fat_id', 'epik', 'srsltid',
    'ref_src', 'ref_url', '_ga', '_gl', 'cmpid', 'zanpid', 'xtor', 'irclickid', 'admitad_uid', 'tduid', 'awc', 'obclid',
    'dicbo', '_branch_match_id', '_bta_tid', '_bta_c', 'mbid', 'soc_src', 'soc_trk', 'mibextid', '__cft__', '__tn__',
    'hsctatracking', 'spm', 'scm', 'share_id', 'si'
  ]);
  const TRACK_BY_SITE = [
    [/(^|\.)google\.[a-z.]+$/, ['ved', 'ei', 'oq', 'sxsrf', 'sca_esv', 'gs_lcrp', 'gs_lp', 'uact', 'aqs', 'sourceid', 'sclient', 'iflsig', 'rlz', 'bih', 'biw']],
    [/(^|\.)bing\.com$/, ['form', 'sk', 'sp', 'cvid', 'qs', 'sc', 'pq', 'ghsh', 'ghacc', 'ghpl']],
    [/(^|\.)amazon\.[a-z.]+$/, ['_encoding', 'psc', 'refrid', 'qid', 'sr', 'dib', 'dib_tag', 'content-id', 'ascsubtag', 'linkcode', 'creativeasin', 'smid', 'th', 'sprefix', 'crid', 'ref', 'tag']],
    [/(^|\.)(youtube\.com|youtu\.be)$/, ['feature', 'pp', 'embeds_referring_euri', 'source_ve_path', 'ab_channel']],
    [/(^|\.)(twitter\.com|x\.com)$/, ['s', 't']],
    [/(^|\.)tiktok\.com$/, ['is_from_webapp', 'sender_device', '_r', '_t', 'refer', 'is_copy_url', 'share_app_id', 'share_link_id', 'share_item_id']],
    [/(^|\.)linkedin\.com$/, ['trk', 'trkinfo', 'lipi', 'originalsubdomain', 'refid']],
    [/(^|\.)reddit\.com$/, ['rdt', 'correlation_id', 'ref_source', 'ref_campaign', 'ref', '$deep_link']],
    [/(^|\.)aliexpress\.[a-z.]+$/, ['pvid', 'algo_pvid', 'algo_exp_id', 'gps-id', 'scm_id', 'scm-url', 'pdp_npi', 'curpageloguid', 'sk']],
    [/(^|\.)facebook\.com$/, ['ref', 'rdid', 'refsrc', 'hc_ref', 'fref']],
    [/(^|\.)instagram\.com$/, ['img_index']],
    [/(^|\.)yandex\.[a-z.]+$/, ['suggest_reqid', 'from']]
  ];

  function isTracker(name, host) {
    const key = name.toLowerCase();
    if (TRACK_ANYWHERE.has(key)) return key !== 'si' || /(^|\.)(youtube\.com|youtu\.be|spotify\.com|instagram\.com)$/.test(host);
    if (TRACK_PREFIXES.some((prefix) => key.startsWith(prefix))) return true;
    return TRACK_BY_SITE.some(([pattern, keys]) => pattern.test(host) && keys.includes(key));
  }

  function cleanUrl(href) {
    let url;
    try { url = new URL(href); } catch { return { url: href, removed: 0 }; }
    if (!/^https?:$/.test(url.protocol)) return { url: href, removed: 0 };
    const host = url.hostname.toLowerCase();
    let removed = 0;
    for (const name of [...url.searchParams.keys()]) {
      if (isTracker(name, host)) {
        url.searchParams.delete(name);
        removed++;
      }
    }
    if (/(^|\.)amazon\.[a-z.]+$/.test(host)) {
      const path = url.pathname.replace(/\/ref=[^/]*$/i, '');
      if (path !== url.pathname) {
        url.pathname = path;
        removed++;
      }
    }
    if (url.hash && /^#(:~:|utm_)/.test(url.hash)) {
      url.hash = '';
      removed++;
    }
    let result = url.toString();
    if (!url.search && result.includes('?') && !url.hash) result = result.replace(/\?$/, '');
    return { url: result, removed };
  }

  function normalizeUrl(href) {
    try {
      const url = new URL(cleanUrl(href).url);
      let path = url.pathname;
      if (path.length > 1) path = path.replace(/\/+$/, '');
      const keepHash = /^#[!/]/.test(url.hash) ? url.hash : '';
      return `${url.protocol}//${url.host.toLowerCase()}${path}${url.search}${keepHash}`;
    } catch {
      return href;
    }
  }

  function hostOf(href) {
    try { return new URL(href).hostname.replace(/^www\./, ''); } catch { return ''; }
  }

  return { isTracker, cleanUrl, normalizeUrl, hostOf };
});
