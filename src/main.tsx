import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import "./index.css";

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Saboriza: elemento principal da página não encontrado.");
}

const root = createRoot(rootElement);

function showStartupError(message: string) {
  root.render(
    <main
      role="alert"
      style={{
        minHeight: "100vh",
        display: "grid",
        placeContent: "center",
        padding: "2rem",
        background: "#f5f7f4",
        color: "#153728",
        fontFamily: "sans-serif",
      }}
    >
      <h1>Saboriza temporariamente indisponível</h1>
      <p>{message}</p>
    </main>,
  );
}

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error("Saboriza: configure VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY na hospedagem.");
  showStartupError("A conexão com o banco de dados ainda não foi configurada. Tente novamente mais tarde.");
} else {
  import("./App")
    .then(({ App }) => {
      root.render(
        <StrictMode>
          <BrowserRouter>
            <App />
          </BrowserRouter>
        </StrictMode>,
      );
    })
    .catch((error: unknown) => {
      console.error("Saboriza: falha ao iniciar a aplicação.", error);
      showStartupError("Não foi possível carregar o catálogo. Tente novamente mais tarde.");
    });
}
