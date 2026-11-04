// Login opcional com Google via Supabase Auth.
//
// O lobby inicia o fluxo e guarda uma copia enxuta da sessao para o jogo ler
// pelo JavaScriptBridge (src/core/Auth.gd). O jogo nunca carrega supabase-js:
// so a pagina do lobby tem o botao e o cliente OAuth.
(function () {
  const SUPABASE_URL = "https://ulchgvwidctalaaxugeg.supabase.co";
  // Chave publishable, publica por design. A service_role nunca vai ao cliente.
  const SUPABASE_KEY = "sb_publishable_zcbcBMNOhVEfwrQaujRgvQ_eqUEzKeo";
  const SUPABASE_CDN =
    "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js";
  const SESSION_KEY = "bs_auth_session";
  // Chave do supabase-js; mantida estavel para o retorno do OAuth (PKCE)
  // encontrar o verificador gravado antes de sair para o Google.
  const CLIENT_STORAGE_KEY = "bs_supabase_auth";
  const LOGIN_LABEL = "Entrar com Google";
  const LOGOUT_LABEL = "Sair";

  let button = null;
  let clientPromise = null;

  function decodePayload(token) {
    try {
      const part = String(token).split(".")[1];
      if (!part) return {};
      const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
      const padded = base64.padEnd(
        base64.length + ((4 - (base64.length % 4)) % 4),
        "="
      );
      return JSON.parse(atob(padded));
    } catch (_error) {
      return {};
    }
  }

  // A sessao guardada aqui e so o que o jogo precisa: token, UUID e validade.
  function readSession() {
    let stored;
    try {
      stored = JSON.parse(localStorage.getItem(SESSION_KEY) || "null");
    } catch (_error) {
      return null;
    }
    if (!stored || typeof stored.token !== "string" || !stored.token) return null;
    if (stored.exp && stored.exp * 1000 <= Date.now()) {
      try {
        localStorage.removeItem(SESSION_KEY);
      } catch (_error) {
        // Sem storage nao ha copia para limpar.
      }
      return null;
    }
    return stored;
  }

  function saveSession(session) {
    try {
      if (!session || !session.access_token) {
        localStorage.removeItem(SESSION_KEY);
        return;
      }
      const payload = decodePayload(session.access_token);
      localStorage.setItem(SESSION_KEY, JSON.stringify({
        token: session.access_token,
        user_id: (session.user && session.user.id) || payload.sub || "",
        exp: session.expires_at || payload.exp || 0,
      }));
    } catch (_error) {
      // Sem storage a sessao vale so nesta pagina; o jogo nao a ve.
    }
  }

  window.bsAuthSession = readSession;
  window.bsAuthToken = function () {
    const session = readSession();
    return session ? session.token : "";
  };
  window.bsAuthUserId = function () {
    const session = readSession();
    return session ? session.user_id : "";
  };

  function loadSupabase() {
    if (window.supabase) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = SUPABASE_CDN;
      script.async = true;
      script.onload = resolve;
      script.onerror = () => reject(new Error("supabase-js indisponivel"));
      document.head.appendChild(script);
    });
  }

  // A copia enxuta pode estar vencida enquanto o supabase-js ainda guarda um
  // refresh token valido. Nesse caso vale a pena carregar o cliente para
  // renovar a sessao em silencio antes de oferecer o login de novo.
  function hasSupabaseSession() {
    try {
      return Boolean(localStorage.getItem(CLIENT_STORAGE_KEY));
    } catch (_error) {
      return false;
    }
  }

  function ensureClient() {
    if (!clientPromise) {
      clientPromise = loadSupabase().then(() => {
        const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
          auth: {
            storageKey: CLIENT_STORAGE_KEY,
            flowType: "pkce",
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: true,
          },
        });
        // O callback roda fora de um await: so grava a copia e atualiza a tela.
        client.auth.onAuthStateChange((_event, session) => {
          saveSession(session);
          applyAnalyticsUserId(session && session.user ? session.user.id : "");
          updateButton();
        });
        return client;
      });
    }
    return clientPromise;
  }

  function applyAnalyticsUserId(userId) {
    if (userId && window.bsSetUserId) {
      window.bsSetUserId(userId);
    } else if (window.bsClearUserId) {
      window.bsClearUserId();
    }
  }

  function updateButton() {
    if (!button) return;
    button.hidden = false;
    button.textContent = readSession() ? LOGOUT_LABEL : LOGIN_LABEL;
  }

  function showAuthError() {
    if (!button) return;
    button.disabled = true;
    button.textContent = "Login indisponível";
    window.setTimeout(() => {
      button.disabled = false;
      updateButton();
    }, 4000);
  }

  function cleanReturnUrl() {
    const url = new URL(location.href);
    url.searchParams.delete("code");
    url.searchParams.delete("error");
    url.searchParams.delete("error_description");
    url.searchParams.delete("error_code");
    if (url.hash) url.hash = "";
    history.replaceState(null, "", url.pathname + url.search);
  }

  async function onButtonClick() {
    if (button.disabled) return;
    if (readSession()) {
      button.disabled = true;
      try {
        const client = await ensureClient();
        await client.auth.signOut();
      } catch (_error) {
        // Sem servidor, a copia local sai mesmo assim.
      }
      saveSession(null);
      applyAnalyticsUserId("");
      button.disabled = false;
      updateButton();
      return;
    }

    button.disabled = true;
    try {
      const client = await ensureClient();
      const { error } = await client.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: location.origin + "/" },
      });
      if (error) throw error;
      // A pagina sai para o Google e volta em "/" com ?code=.
    } catch (error) {
      console.error("login Google:", error);
      showAuthError();
    }
  }

  async function finishOAuthReturn() {
    try {
      const client = await ensureClient();
      const { data, error } = await client.auth.getSession();
      if (error) {
        console.error("sessao:", error);
        showAuthError();
        return;
      }
      if (data && data.session) {
        saveSession(data.session);
        applyAnalyticsUserId(data.session.user ? data.session.user.id : "");
      }
    } catch (error) {
      console.error("login Google:", error);
      showAuthError();
    } finally {
      cleanReturnUrl();
      updateButton();
    }
  }

  function initLobby() {
    button = document.getElementById("auth");
    if (!button) return;
    updateButton();
    button.addEventListener("click", onButtonClick);

    const session = readSession();
    if (session) applyAnalyticsUserId(session.user_id);

    const params = new URLSearchParams(location.search);
    const returning = params.has("code") || params.has("error");
    if (returning) {
      finishOAuthReturn();
      return;
    }
    if (!session && !hasSupabaseSession()) return;
    // Renova a sessao guardada, inclusive quando a copia enxuta venceu mas o
    // refresh token do supabase-js ainda e valido.
    ensureClient()
      .then((client) => client.auth.getSession())
      .then(({ data }) => {
        if (data && data.session) {
          saveSession(data.session);
          applyAnalyticsUserId(data.session.user ? data.session.user.id : "");
        } else {
          saveSession(null);
          applyAnalyticsUserId("");
        }
        updateButton();
      })
      .catch(() => {});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initLobby);
  } else {
    initLobby();
  }
})();
