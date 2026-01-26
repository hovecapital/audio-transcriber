type MicRecorderAPI = {
  sendReady: () => void;
  sendError: (error: string) => void;
  sendData: (data: ArrayBuffer) => void;
  onStopRecording: (callback: () => void) => void;
};

declare global {
  interface Window {
    micRecorderAPI: MicRecorderAPI;
  }
}

let mediaRecorder: MediaRecorder | null = null;
let audioChunks: Blob[] = [];

async function startRecording(): Promise<void> {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        sampleRate: 16000,
        channelCount: 1,
      },
    });

    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : 'audio/webm';

    mediaRecorder = new MediaRecorder(stream, { mimeType });
    audioChunks = [];

    mediaRecorder.ondataavailable = (event: BlobEvent): void => {
      if (event.data.size > 0) {
        audioChunks.push(event.data);
      }
    };

    mediaRecorder.onstop = async (): Promise<void> => {
      stream.getTracks().forEach((track) => track.stop());

      const audioBlob = new Blob(audioChunks, { type: mimeType });
      const arrayBuffer = await audioBlob.arrayBuffer();
      window.micRecorderAPI.sendData(arrayBuffer);
    };

    mediaRecorder.start(1000);
    window.micRecorderAPI.sendReady();
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    window.micRecorderAPI.sendError(message);
  }
}

function stopRecording(): void {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.stop();
  }
}

window.micRecorderAPI.onStopRecording(() => {
  stopRecording();
});

startRecording();
