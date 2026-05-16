import "./tailwind.input.css";

const FEEDBACK_SCRIPT_ID = "feedback-one-sdk";
const FEEDBACK_PROJECT_ID = "019e3269-74e1-7a61-8e62-27959f5d5442";

type ElmPagesInit = {
  load: (elmLoaded: Promise<unknown>) => Promise<void>;
  flags: unknown;
};

function loadFeedbackButton() {
  if (document.getElementById(FEEDBACK_SCRIPT_ID)) return;

  const script = document.createElement("script");
  script.id = FEEDBACK_SCRIPT_ID;
  script.src = "https://sdk.feedback.one/v0/core.min.js";
  script.dataset.projectId = FEEDBACK_PROJECT_ID;
  script.defer = true;
  document.head.appendChild(script);
}

const config: ElmPagesInit = {
  load: async function (elmLoaded) {
    loadFeedbackButton();
    const app = await elmLoaded;
    console.log("App loaded", app);
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};

export default config;
