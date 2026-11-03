// OAuth client IDs for Connect Google Meet, from the Google Cloud project
// behind Firebase (theotutoring-2e83f), with the Google Meet REST API turned
// on. Client IDs are public, so they are safe to commit. Never put a client
// secret here.
//
// While one is empty, Connect Google Meet shows "Google Meet wasn't
// connected" on that platform instead of opening Google.
//
// Android needs no ID here: Google recognises the app by its package name
// (com.example.theo_tutoring_app) and the SHA-1 of the key that signed the
// build, registered as an Android client in the same Cloud project.

/// The "Web application" client, for the web app on localhost:7357 (only
/// works once http://localhost and http://localhost:7357 are listed as its
/// JavaScript origins). Ends in .apps.googleusercontent.com.
const googleWebClientId =
    '858392313917-p724h6112blpe7fm1c4qu882skf699dh.apps.googleusercontent.com';

/// The "iOS" client for bundle ID com.example.theoTutoringApp.
/// Add its reversed form (`com.googleusercontent.apps.123-abc`, the
/// REVERSED_CLIENT_ID) as a URL scheme in ios/Runner/Info.plist at the same
/// time: without it the app closes as soon as Google's sign-in opens.
const googleIosClientId =
    '858392313917-29gqfc9sc4d27mcovjkr79im5oajc6n1.apps.googleusercontent.com';
