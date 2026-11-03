// Ponte comum entre as páginas do site e o jogo (via JavaScriptBridge).
// O GDScript chama bsPwaCanInstall/bsPwaIsInstalled/bsPwaInstall no menu;
// o lobby usa as mesmas funções no botão "Instalar app".
(function () {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => {});
  }

  let installPrompt = null;

  window.bsPwaIsInstalled = function () {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.matchMedia("(display-mode: fullscreen)").matches ||
      window.navigator.standalone === true
    );
  };

  window.bsPwaIsIos = function () {
    const ua = window.navigator.userAgent || "";
    const ipadOnMac =
      window.navigator.platform === "MacIntel" &&
      window.navigator.maxTouchPoints > 1;
    return /iphone|ipad|ipod/i.test(ua) || ipadOnMac;
  };

  window.bsPwaCanInstall = function () {
    return !!installPrompt && !window.bsPwaIsInstalled();
  };

  window.bsPwaInstall = function () {
    if (!installPrompt) return "unavailable";
    const prompt = installPrompt;
    installPrompt = null;
    prompt.prompt();
    return prompt.userChoice.then((choice) => choice.outcome);
  };

  function updateInstallButton() {
    const button = document.getElementById("install");
    if (!button) return;
    const available =
      !window.bsPwaIsInstalled() &&
      (window.bsPwaCanInstall() || window.bsPwaIsIos());
    button.hidden = !available;
  }

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    installPrompt = event;
    updateInstallButton();
  });

  window.addEventListener("appinstalled", () => {
    installPrompt = null;
    updateInstallButton();
  });

  function wireInstallButton() {
    const button = document.getElementById("install");
    if (!button) return;
    button.addEventListener("click", () => {
      if (window.bsPwaCanInstall()) {
        window.bsPwaInstall();
        return;
      }
      window.alert(
        "No iPhone/iPad: toque em Compartilhar e escolha " +
          "\"Adicionar à Tela de Início\".\n\n" +
          "No Chrome/Edge: menu do navegador > Instalar aplicativo."
      );
    });
    updateInstallButton();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", wireInstallButton);
  } else {
    wireInstallButton();
  }
})();
