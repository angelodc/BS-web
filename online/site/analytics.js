// GA4 enxuto do build web: usuarios ativos, resolucao do canvas e um user_id
// pseudonimo (UUID do Supabase). O jogo chama estas funcoes pelo
// JavaScriptBridge (ver src/core/Analytics.gd).
(function () {
  // Preencher com o ID da propriedade GA4 (G-...). Vazio desliga o GA4 inteiro
  // sem quebrar o jogo, que e o estado esperado ate a propriedade existir.
  const MEASUREMENT_ID = "G-Z4YHVSLCRL";
  const CONSENT_KEY = "bs_analytics_consent";
  const BANNER_ID = "bs-consent";
  const MAX_PENDING_EVENTS = 20;
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  window.dataLayer = window.dataLayer || [];
  function gtag() {
    window.dataLayer.push(arguments);
  }
  window.gtag = gtag;

  // Consent mode v2: tudo negado ate o banner registrar a escolha, e o gtag
  // nem e carregado antes disso.
  gtag("consent", "default", {
    ad_storage: "denied",
    ad_user_data: "denied",
    ad_personalization: "denied",
    analytics_storage: "denied",
  });
  gtag("set", "ads_data_redaction", true);

  // Navegacao privada pode recusar o localStorage; a escolha da pagina fica
  // na memoria para o banner nao reaparecer no mesmo carregamento.
  let memoryConsent = null;
  const pendingEvents = [];
  let pendingUserId = "";

  // null = ainda sem escolha, que e o unico estado em que o banner aparece.
  function storedConsent() {
    try {
      const stored = localStorage.getItem(CONSENT_KEY);
      if (stored === "granted" || stored === "denied") return stored;
    } catch (_error) {
      // Sem storage: cai na escolha em memoria.
    }
    return memoryConsent;
  }

  function grantConsent() {
    gtag("consent", "update", {
      analytics_storage: "granted",
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
    });
  }

  function applyUserId() {
    if (pendingUserId) gtag("set", { user_id: pendingUserId });
  }

  function flushPendingEvents() {
    applyUserId();
    for (const [name, params] of pendingEvents.splice(0)) {
      gtag("event", name, params);
    }
  }

  let gtagLoaded = false;

  // Sem o "Aceitar" o Google nao recebe nem um ping, e o texto do banner vale
  // para qualquer escolha.
  function loadGtag() {
    if (!MEASUREMENT_ID || gtagLoaded) return;
    gtagLoaded = true;
    const script = document.createElement("script");
    script.async = true;
    script.src =
      "https://www.googletagmanager.com/gtag/js?id=" +
      encodeURIComponent(MEASUREMENT_ID);
    document.head.appendChild(script);
    gtag("js", new Date());
    gtag("config", MEASUREMENT_ID);
  }

  if (storedConsent() === "granted") {
    grantConsent();
    loadGtag();
  }

  // O banner grava a escolha aqui e atualiza o GA4 na hora, sem recarregar.
  window.bsConsent = function (granted) {
    const choice = granted ? "granted" : "denied";
    memoryConsent = choice;
    try {
      localStorage.setItem(CONSENT_KEY, choice);
    } catch (_error) {
      // Sem storage: a escolha vale so para esta pagina.
    }
    gtag("consent", "update", { analytics_storage: choice });
    if (choice === "granted") {
      loadGtag();
      flushPendingEvents();
    } else {
      pendingEvents.length = 0;
      pendingUserId = "";
    }
    hideConsentBanner();
    return choice;
  };

  window.bsHasConsent = function () {
    return storedConsent() === "granted";
  };

  window.bsConsentChoice = function () {
    return storedConsent() || "";
  };

  window.bsTrack = function (name, params) {
    if (!MEASUREMENT_ID || !name) return false;
    const eventName = String(name);
    const eventParams = params || {};
    const choice = storedConsent();
    if (choice === "granted") {
      gtag("event", eventName, eventParams);
      return true;
    }
    // Antes da escolha o evento espera na fila e sai junto com o "Aceitar";
    // depois de um "Recusar" ele e descartado.
    if (choice === null) {
      pendingEvents.push([eventName, eventParams]);
      if (pendingEvents.length > MAX_PENDING_EVENTS) pendingEvents.shift();
    }
    return false;
  };

  // GA4 espera user_id sem PII; aqui so passa UUID, nunca e-mail ou nome.
  window.bsSetUserId = function (id) {
    const value = String(id || "").trim();
    if (!MEASUREMENT_ID || !UUID_RE.test(value)) return false;
    pendingUserId = value;
    if (storedConsent() === "granted") applyUserId();
    return true;
  };

  // Usado no logout: os eventos seguintes deixam de carregar a conta.
  window.bsClearUserId = function () {
    pendingUserId = "";
    if (MEASUREMENT_ID) gtag("set", { user_id: null });
  };

  // Lido pelo jogo ao abrir, para registrar a resolucao real do canvas.
  // canvas_* vem em pixels do dispositivo; window_* em CSS pixels, com o dpr
  // separado para comparar as duas medidas.
  window.bsGameMetrics = function () {
    const canvas = document.querySelector("canvas");
    const dpr = window.devicePixelRatio || 1;
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true;
    const fullscreen =
      window.matchMedia("(display-mode: fullscreen)").matches ||
      !!document.fullscreenElement;
    return JSON.stringify({
      canvas_w: canvas ? Math.round(canvas.width) : 0,
      canvas_h: canvas ? Math.round(canvas.height) : 0,
      window_w: Math.round(window.innerWidth),
      window_h: Math.round(window.innerHeight),
      dpr: Math.round(dpr * 100) / 100,
      mode: standalone ? "standalone" : fullscreen ? "fullscreen" : "browser",
    });
  };

  function hideConsentBanner() {
    const banner = document.getElementById(BANNER_ID);
    if (banner) banner.remove();
  }

  function buildConsentBanner(force) {
    // Sem propriedade GA4 nao ha medicao, entao nao ha o que consentir.
    if (!MEASUREMENT_ID) return;
    if (!force && storedConsent() !== null) return;
    if (document.getElementById(BANNER_ID)) return;

    const style = document.createElement("style");
    style.id = "bs-consent-style";
    style.textContent = `
      #${BANNER_ID}{position:fixed;left:0;right:0;bottom:0;z-index:2147483647;
        display:flex;flex-wrap:wrap;align-items:center;justify-content:center;
        gap:12px 18px;padding:14px 18px;background:#191d22;color:#e6e6e6;
        border-top:1px solid #3a3f47;font:14px/1.45 system-ui,sans-serif;
        box-shadow:0 -8px 24px rgba(0,0,0,.35)}
      #${BANNER_ID} p{margin:0;max-width:46rem}
      #${BANNER_ID} .bs-consent-actions{display:flex;gap:8px}
      #${BANNER_ID} button{padding:8px 16px;border-radius:6px;
        border:1px solid #3a3f47;background:#1d2127;color:inherit;
        font:inherit;cursor:pointer}
      #${BANNER_ID} button.bs-consent-accept{background:#2b5c3f;
        border-color:#3b7a54}
      #${BANNER_ID} button:hover{filter:brightness(1.15)}
    `;
    document.head.appendChild(style);

    const banner = document.createElement("div");
    banner.id = BANNER_ID;
    banner.setAttribute("role", "region");
    banner.setAttribute("aria-label", "Consentimento de medição");

    const text = document.createElement("p");
    text.textContent =
      "O jogo usa o Google Analytics para medir o uso e as resoluções de " +
      "tela. Nada é enviado antes da sua escolha.";

    const actions = document.createElement("div");
    actions.className = "bs-consent-actions";

    const reject = document.createElement("button");
    reject.type = "button";
    reject.className = "bs-consent-reject";
    reject.textContent = "Recusar";
    reject.addEventListener("click", () => window.bsConsent(false));

    const accept = document.createElement("button");
    accept.type = "button";
    accept.className = "bs-consent-accept";
    accept.textContent = "Aceitar";
    accept.addEventListener("click", () => window.bsConsent(true));

    actions.append(reject, accept);
    banner.append(text, actions);
    document.body.append(banner);
  }

  // O lobby expoe um link "Cookies" para rever a escolha a qualquer momento.
  function wireConsentLink() {
    const link = document.getElementById("cookies");
    if (!link || !MEASUREMENT_ID) return;
    link.hidden = false;
    link.addEventListener("click", () => buildConsentBanner(true));
  }

  function startConsentUi() {
    buildConsentBanner();
    wireConsentLink();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startConsentUi);
  } else {
    startConsentUi();
  }
})();
