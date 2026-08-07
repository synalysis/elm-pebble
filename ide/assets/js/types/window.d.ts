import type {EmbeddedEmulatorPersistedState} from "./embedded_emulator_state"

export {}

type AuthRefreshDetail = {
  id_token?: string
  redirect_to?: string
}

type AuthRefreshFailedDetail = {
  error?: string
}

export type FirebaseConfig = Record<string, unknown>

type FirebaseUser = {
  getIdToken: (forceRefresh?: boolean) => Promise<string>
}

type FirebaseAuthResult = {
  user: FirebaseUser | null
}

type FirebaseAuthProvider = {
  addScope: (scope: string) => void
}

type FirebaseAuthInstance = {
  signInWithPopup: (provider: unknown) => Promise<FirebaseAuthResult>
  getRedirectResult: () => Promise<FirebaseAuthResult>
  onAuthStateChanged: (callback: (user: FirebaseUser | null) => void) => () => void
  signOut: () => Promise<void>
  currentUser: FirebaseUser | null
}

type FirebaseAuthNamespace = {
  GithubAuthProvider: new () => FirebaseAuthProvider
  OAuthProvider: new (providerId: string) => FirebaseAuthProvider
  GoogleAuthProvider: new () => FirebaseAuthProvider
}

export type FirebaseNamespace = {
  apps: unknown[]
  initializeApp: (config: FirebaseConfig) => unknown
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
    "elm-pebble-auth-refresh-failed": CustomEvent<AuthRefreshFailedDetail>
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
