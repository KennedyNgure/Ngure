/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Initialize the Admin SDK (required for deleting other users'
// Auth accounts and doing server-side Firestore cleanup).
admin.initializeApp();

// ============================================================
// deleteUserAccount
// ============================================================
//
// REQUIRED Cloud Function for the admin "Delete Account" button.
//
// The Flutter client SDK can only delete the SIGNED-IN user's
// Firebase Authentication account — never another user's. So
// VerifyPropertyOwnersPage calls this callable function with the
// target owner's uid. The Admin SDK does the auth deletion, and
// also cleans up Firestore data server-side so nothing is left
// behind even if the client-side cleanup was interrupted.
//
// Deploy:  firebase deploy --only functions
exports.deleteUserAccount = onCall(async (request) => {
  const {uid} = request.data || {};

  // 1. Validate input.
  if (!uid || typeof uid !== "string") {
    throw new HttpsError("invalid-argument", "uid is required.");
  }

  // 2. ONLY ADMINS may call this. The caller's Firestore profile
  //    must have role == 'admin'. This check is enforced by the
  //    function itself (App Check + auth), not just the client.
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  if (callerUid === uid) {
    throw new HttpsError(
      "failed-precondition",
      "Admins cannot delete their own account here."
    );
  }

  const callerDoc = await admin
    .firestore()
    .collection("users")
    .doc(callerUid)
    .get();

  if (callerDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admins only.");
  }

  // 3. Delete all the owner's properties (server-side backup of
  //    the client-side cleanup; works even if the client was
  //    interrupted mid-way).
  const props = await admin
    .firestore()
    .collection("properties")
    .where("ownerId", "==", uid)
    .get();

  const batchDeletes = [];
  for (let i = 0; i < props.docs.length; i += 450) {
    const batch = admin.firestore().batch();
    props.docs.slice(i, i + 450).forEach((d) => batch.delete(d.ref));
    batchDeletes.push(batch.commit());
  }
  await Promise.all(batchDeletes);

  // 4. Delete the Firestore user document.
  await admin.firestore().collection("users").doc(uid).delete();

  // 5. Delete the Firebase Authentication account.
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    // The auth user may already be gone — that is fine.
    if (e.code !== "auth/user-not-found") {
      throw new HttpsError("internal", e.message);
    }
  }

  logger.info("Deleted user account", {structuredData: true, uid});
  return {success: true};
});