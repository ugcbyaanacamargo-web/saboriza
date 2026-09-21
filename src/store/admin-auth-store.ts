import { create } from "zustand";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";

interface AdminAuthState {
  session: Session | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  init: () => void;
  login: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
  logout: () => Promise<void>;
}

// Being logged in does NOT grant Saboriza admin access. Only the Supabase
// project owner can assign app_metadata.saboriza_role = "admin".
function hasAdminRole(session: Session | null): boolean {
  return session?.user?.app_metadata?.saboriza_role === "admin";
}

function adminSession(session: Session | null) {
  const authorized = hasAdminRole(session);
  return { session: authorized ? session : null, isAuthenticated: authorized, isLoading: false };
}

export const useAdminAuthStore = create<AdminAuthState>((set) => ({
  session: null,
  isAuthenticated: false,
  isLoading: true,

  init: () => {
    supabase.auth.getSession()
      .then(({ data, error }) => {
        if (error) console.error("Falha ao carregar sessão administrativa:", error.message);
        set(adminSession(error ? null : data.session));
      })
      .catch((error: unknown) => {
        console.error("Falha ao iniciar autenticação:", error);
        set(adminSession(null));
      });
    supabase.auth.onAuthStateChange((_event, session) => {
      set(adminSession(session));
    });
  },

  login: async (email, password) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.session) {
      return { success: false, error: error?.message ?? "E-mail ou senha inválidos" };
    }
    if (!hasAdminRole(data.session)) {
      await supabase.auth.signOut();
      set(adminSession(null));
      return { success: false, error: "Conta sem autorização administrativa no Saboriza." };
    }
    set(adminSession(data.session));
    return { success: true };
  },

  logout: async () => {
    await supabase.auth.signOut();
    set(adminSession(null));
  },
}));
