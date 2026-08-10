export const tdInit: (onReceive: (json: string) => void) => void;
export const tdSend: (json: string) => void;
export const tdExecute: (json: string) => string;
export const tdDestroy: () => void;
export const tgcallsCreate: (
  onState: (connected: boolean) => void,
  onBroadcastRequest: (
    requestId: number, kind: number, timestampMs: number,
    durationMs: number, channelId: number, quality: number
  ) => void,
  onAudioActivity: (audioSourceId: number, speaking: boolean) => void,
  onLocalVideoState: (mode: number, active: boolean, error: number) => void,
  onVideoGeometry: (endpointId: string, width: number, height: number) => void
) => boolean;
export const tgcallsEmitJoinPayload: (onPayload: (audioSourceId: number, payload: string) => void) => void;
export const tgcallsSetJoinResponse: (payload: string) => void;
export const tgcallsSetConnectionMode: (mode: number, isUnifiedBroadcast: boolean) => void;
export const tgcallsScreenShareCreate: (
  onState: (connected: boolean) => void,
  onLocalVideoState: (mode: number, active: boolean, error: number) => void,
  width: number,
  height: number
) => boolean;
export const tgcallsScreenShareEmitJoinPayload: (
  onPayload: (audioSourceId: number, payload: string) => void
) => void;
export const tgcallsScreenShareSetJoinResponse: (payload: string) => void;
export const tgcallsScreenShareSetConnectionMode: () => void;
export const tgcallsScreenShareDestroy: () => void;
export const tgcallsCompleteBroadcastTime: (requestId: number, timestampMs: number) => void;
export const tgcallsCompleteBroadcastPart: (
  requestId: number, timestampMs: number, status: number,
  responseTimestamp: number, data: Uint8Array
) => void;
export const tgcallsSetMuted: (muted: boolean) => boolean;
// mode: 0=off, 1=front camera, 2=back camera, 3=screen capture.
export const tgcallsSetLocalVideo: (mode: number, width: number, height: number) => boolean;
export const tgcallsSetLocalVideoSurface: (
  surfaceId: string, surfaceWidth: number, surfaceHeight: number
) => void;
export const tgcallsResumeMedia: () => void;
export const tgcallsSetVideoSurface: (
  endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
) => void;
export const tgcallsSetVideoChannel: (endpointId: string, audioSsrc: number, ssrcGroups: string) => void;
export const tgcallsRemoveVideoChannel: (endpointId: string) => void;
export const tgcallsClearVideo: () => void;
export const tgcallsDestroy: () => void;

// --- 1对1 通话（tgcalls Instance/InstanceV2） ---
// state: 0=connecting 1=ready 2=failed 3=reconnecting
export const callCreate: (
  encryptionKeyBase64: string, isOutgoing: boolean, serversJson: string, isVideo: boolean,
  remoteVersionsJson: string,
  onState: (state: number) => void,
  onSignalingData: (dataBase64: string) => void,
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void
) => boolean;
export const callDestroy: () => void;
export const callReceiveSignaling: (dataBase64: string) => void;
export const callSetMuted: (muted: boolean) => void;
// mode: 0=off, 1=front camera, 2=back camera.
export const callSetVideo: (mode: number) => void;
export const callSetAudioOutput: (speaker: boolean) => void;
export const callSetLocalVideoSurface: (surfaceId: string) => void;
export const callSetRemoteVideoSurface: (surfaceId: string) => void;
export const callVersions: () => string;
