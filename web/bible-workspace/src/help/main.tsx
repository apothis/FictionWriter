import React from "react";
import ReactDOM from "react-dom/client";
import "../styles.css";
import { HelpApp } from "./HelpApp";

const root = document.getElementById("root");
if (root) {
  ReactDOM.createRoot(root).render(
    <React.StrictMode>
      <HelpApp />
    </React.StrictMode>
  );
}
