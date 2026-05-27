import type {EmbeddedEmulatorPersistedState} from "./embedded_emulator_state"

export {}

type AuthRefreshDetail = {
  id_token?: string
  redirect_to?: string
}

type FirebaseUser = {
  getIdToken: (forceRefresh?: boolean) => Promise<string>
}

type FirebaseAuthResult = {
  user: FirebaseUser
}

type FirebaseAuthInstance = {
  signInWithPopup: (provider: unknown) => Promise<FirebaseAuthResult>
  signOut: () => Promise<void>
  currentUser: FirebaseUser | null
}

type FirebaseAuthNamespace = {
  GithubAuthProvider: new () => unknown
  OAuthProvider: new (providerId: string) => unknown
  GoogleAuthProvider: new () => unknown
}

export type FirebaseNamespace = {
  apps: unknown[]
  initializeApp: (config: Record<string, unknown>) => unknown
  auth: FirebaseAuthNamespace & (() => FirebaseAuthInstance)
}

declare global {
  interface WebSocket {
    __elmPebbleVncDiag?: boolean
  }

  interface HTMLElement {
    __embeddedEmulatorHost?: {
      sendAccelSample: (x: number, y: number, z: number) => void
    }
  }

  interface WindowEventMap {
    "elm-pebble-auth-refreshed": CustomEvent<AuthRefreshDetail>
    "phx:ide-theme-changed": CustomEvent<{theme?: string}>
    "phx:open_url": CustomEvent<{url?: string}>
  }

  interface Window {
    __elmPebbleEmbeddedEmulatorStates?: Map<string, EmbeddedEmulatorPersistedState>
    __elmPebbleCompanionSimulatorSettings?: unknown
    liveSocket?: unknown
    firebase?: FirebaseNamespace
  }
}
