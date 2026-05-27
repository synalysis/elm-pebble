import "./tailwind.input.css";

const FEEDBACK_PROJECT_ID = "019e3269-74e1-7a61-8e62-27959f5d5442";
const FEEDBACK_SDK_URL = "https://sdk.feedback.one/v0/core.min.js";

type FeedbackOneApi = {
  init: (options: {
    projectId: string;
    persistent?: boolean;
    showDefaultTrigger?: boolean;
  }) => void;
};

type ElmPagesInit = {
  load: (elmLoaded: Promise<unknown>) => Promise<void>;
  flags: unknown;
};

function feedbackAlreadyMounted(): boolean {
  return document.querySelector("feedback-one") !== null;
}

function initFeedbackFromApi(api: FeedbackOneApi) {
  if (feedbackAlreadyMounted()) {
    return;
  }

  api.init({ projectId: FEEDBACK_PROJECT_ID, showDefaultTrigger: true });
}

function ensureFeedbackWidget() {
  const api = (window as Window & { FeedbackOne?: FeedbackOneApi }).FeedbackOne;

  if (api) {
    initFeedbackFromApi(api);
    return;
  }

  const existing = document.querySelector(
    `script[src="${FEEDBACK_SDK_URL}"]`,
  ) as HTMLScriptElement | null;

  if (existing) {
    existing.addEventListener(
      "load",
      () => {
        const loaded = (window as Window & { FeedbackOne?: FeedbackOneApi })
          .FeedbackOne;
        if (loaded) {
          initFeedbackFromApi(loaded);
        }
      },
      { once: true },
    );
    return;
  }

  const script = document.createElement("script");
  script.src = FEEDBACK_SDK_URL;
  script.defer = true;
  script.addEventListener(
    "load",
    () => {
      const loaded = (window as Window & { FeedbackOne?: FeedbackOneApi })
        .FeedbackOne;
      if (loaded) {
        initFeedbackFromApi(loaded);
      }
    },
    { once: true },
  );
  document.head.appendChild(script);
}

const config: ElmPagesInit = {
  load: async function (elmLoaded) {
    await elmLoaded;
    ensureFeedbackWidget();
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};

export default config;
