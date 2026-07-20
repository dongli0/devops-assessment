const supportedEnvironments = new Set([
  "dev",
  "test",
  "perf",
  "staging",
  "production",
]);

const pathEnvironment = window.location.pathname.split("/").filter(Boolean)[0];
const environment = supportedEnvironments.has(pathEnvironment)
  ? pathEnvironment
  : "dev";

const navToggle = document.querySelector(".nav-toggle");
const navLinks = document.querySelector(".nav-links");

function setNavigationOpen(open) {
  if (
    !(navToggle instanceof HTMLButtonElement) ||
    !(navLinks instanceof HTMLElement)
  ) {
    return;
  }

  navToggle.setAttribute("aria-expanded", String(open));
  navLinks.classList.toggle("is-open", open);
}

if (navToggle instanceof HTMLButtonElement && navLinks instanceof HTMLElement) {
  navToggle.addEventListener("click", () => {
    const isOpen = navToggle.getAttribute("aria-expanded") === "true";
    setNavigationOpen(!isOpen);
  });

  navLinks.addEventListener("click", (event) => {
    if (event.target instanceof HTMLAnchorElement) {
      setNavigationOpen(false);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      setNavigationOpen(false);
    }
  });
}

const currentYear = document.querySelector("#current-year");

if (currentYear instanceof HTMLElement) {
  currentYear.textContent = String(new Date().getFullYear());
}

const contactForm = document.querySelector("#contact-form");
const formStatus = document.querySelector("#form-status");

function setFormStatus(message, state) {
  if (!(formStatus instanceof HTMLElement)) {
    return;
  }

  formStatus.textContent = message;
  formStatus.classList.remove("is-success", "is-error");

  if (state) {
    formStatus.classList.add(`is-${state}`);
  }
}

if (contactForm instanceof HTMLFormElement) {
  contactForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const submitButton = contactForm.querySelector('button[type="submit"]');
    const formData = new FormData(contactForm);

    const payload = {
      name: String(formData.get("name") ?? ""),
      email: String(formData.get("email") ?? ""),
      message: String(formData.get("message") ?? ""),
    };

    if (submitButton instanceof HTMLButtonElement) {
      submitButton.disabled = true;
    }

    setFormStatus("Sending...", null);

    try {
      const response = await fetch(`/${environment}/api/contact`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error(
          `Contact request failed with status ${response.status}`,
        );
      }

      contactForm.reset();
      setFormStatus("Message sent successfully.", "success");
    } catch {
      setFormStatus(
        "Unable to send the message. Please try again later.",
        "error",
      );
    } finally {
      if (submitButton instanceof HTMLButtonElement) {
        submitButton.disabled = false;
      }
    }
  });
}
