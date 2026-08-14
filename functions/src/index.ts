/* eslint-disable */
import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

async function getAllTokens(): Promise<string[]> {
  console.log("Getting all tokens...");
  const snapshot = await db.collection("users").get();
  const tokens: string[] = [];
  snapshot.forEach((doc) => {
    const data = doc.data();
    console.log("User doc:", doc.id, "fcmTokens:", data.fcmTokens);
    if (data.fcmToken && typeof data.fcmToken === "string") {
      tokens.push(data.fcmToken);
    }
    if (Array.isArray(data.fcmTokens)) {
      tokens.push(
        ...data.fcmTokens.filter((t: unknown) => typeof t === "string")
      );
    }
  });
  console.log("Total tokens found:", tokens.length);
  return tokens;
}

async function sendToTokens(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  console.log("Sending to tokens:", tokens.length);
  if (tokens.length === 0) {
    console.log("NO TOKENS - skipping");
    return;
  }
  const BATCH = 500;
  for (let i = 0; i < tokens.length; i += BATCH) {
    const batch = tokens.slice(i, i + BATCH);
    const msg: admin.messaging.MulticastMessage = {
      tokens: batch,
      notification: {title, body},
      data,
      android: {
        priority: "high",
        notification: {
          sound: "default",
          channelId: "yitadee_notifications",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };
    const result = await messaging.sendEachForMulticast(msg);
    console.log("FCM result:", result.successCount, "success,", result.failureCount, "failed");
    result.responses.forEach((r, idx) => {
      if (!r.success) console.log("Failed token", idx, r.error);
    });
  }
}

export const onNewSong = onDocumentCreated(
  "songs/{songId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const song = snap.data();
    if (!song) return;
    const title: string = song.title ?? "New Song";
    const artistName: string = song.artistName ?? "";
    const isAlbumTrack = song.albumId && song.albumId !== "";
    if (isAlbumTrack) return;
    const notifTitle = "🎵 New Single";
    const notifBody = artistName ?
      `"${title}" by ${artistName} is now available!` :
      `"${title}" is now available!`;
    console.log("onNewSong triggered:", title);
    const tokens = await getAllTokens();
    await sendToTokens(tokens, notifTitle, notifBody, {
      type: "new_song",
      songId: snap.id,
      title,
      artistName,
    });
  }
);

export const onNewAlbum = onDocumentCreated(
  "albums/{albumId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const album = snap.data();
    if (!album) return;
    const title: string = album.title ?? "New Album";
    const artistName: string = album.artistName ?? "";
    const notifTitle = "💿 New Album";
    const notifBody = artistName ?
      `"${title}" by ${artistName} — listen now!` :
      `"${title}" is now available!`;
    console.log("onNewAlbum triggered:", title);
    const tokens = await getAllTokens();
    await sendToTokens(tokens, notifTitle, notifBody, {
      type: "new_album",
      albumId: snap.id,
      title,
      artistName,
    });
  }
);