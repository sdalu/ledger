"use strict";

// The sign-in and invitation pages: the forms post JSON to sesam's
// routes (the URLs are on the form), show what it refuses with, and go
// on. An invitation's token is the page's fragment, never sent as a URL.
(() => {
    const form = document.querySelector("form[data-page]");
    const problem = document.querySelector(".problem");
    const post = (url, body) => fetch(url, {
        method: "POST", credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
    });
    const refuse = async (response) => {
        const said = await response.json().catch(() => ({}));
        problem.textContent = said.error || `Refused (${response.status}).`;
        problem.hidden = false;
    };
    const token = decodeURIComponent(location.hash.slice(1));

    const greet = async () => {
        const response = await post(form.dataset.check, { token });
        if (!response.ok) return refuse(response);
        const said = await response.json();
        const greeting = document.querySelector("[data-greeting]");
        greeting.textContent = `Choose a password for ${said.data.name}.`;
        greeting.hidden = false;
        form.hidden = false;
    };

    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        problem.hidden = true;
        const fields = Object.fromEntries(new FormData(form));
        if (form.dataset.page === "invite") fields.token = token;
        const response = await post(form.dataset.endpoint, fields);
        if (response.ok) location.href = form.dataset.next;
        else refuse(response);
    });

    if (form.dataset.page === "invite") greet();
})();
