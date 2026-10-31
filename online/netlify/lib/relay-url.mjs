import { getStore } from "@netlify/blobs";

export const STORE_NAME = "relay";
export const ADDRESS_KEY = "address";
export const ENV_URL = (process.env.RELAY_URL || "").replace(/\/+$/, "");

// O endereço público do relay muda sozinho quando o túnel do celular reinicia,
// então quem manda é o registro que o celular grava aqui; o RELAY_URL do Netlify
// fica só como reserva, para o lobby funcionar antes do primeiro registro.
export function relayStore() {
  // Consistência forte: o lobby consulta a cada 5 s e precisa ver na hora o
  // endereço que o celular acabou de registrar.
  return getStore({ name: STORE_NAME, consistency: "strong" });
}

export async function registeredUrl() {
  try {
    const url = await relayStore().get(ADDRESS_KEY);
    if (url) {
      return String(url).trim().replace(/\/+$/, "");
    }
  } catch (error) {
    console.error("relay-url: falha ao ler o registro", error);
  }
  return ENV_URL;
}
