/**
 * Verifies a Google ID token from the iOS app's "Continue with Google" flow.
 *
 * Uses Google's tokeninfo endpoint, which checks the signature and expiry on
 * Google's side. That costs a network round trip per sign-in, which is fine at
 * this volume; at scale, verify the JWT locally against Google's published keys.
 */
export interface GoogleIdentity {
  sub: string;
  email: string;
}

interface TokenInfo {
  aud?: string;
  iss?: string;
  sub?: string;
  email?: string;
  email_verified?: string | boolean;
  exp?: string;
}

export async function verifyGoogleIdToken(idToken: string, audience: string): Promise<GoogleIdentity> {
  const response = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
  );
  if (!response.ok) throw new Error('Google rejected the ID token');

  const claims = (await response.json()) as TokenInfo;

  // A token minted for any other app must not sign in to this one.
  if (claims.aud !== audience) throw new Error('ID token was issued for a different app');
  if (claims.iss !== 'https://accounts.google.com' && claims.iss !== 'accounts.google.com') {
    throw new Error('ID token has an unexpected issuer');
  }
  if (!claims.exp || Number(claims.exp) * 1000 < Date.now()) throw new Error('ID token has expired');
  // An unverified address could belong to someone else, and email is how
  // accounts are matched.
  if (claims.email_verified !== true && claims.email_verified !== 'true') {
    throw new Error('Google account email is not verified');
  }
  if (!claims.sub || !claims.email) throw new Error('ID token is missing identity claims');

  return { sub: claims.sub, email: claims.email.trim().toLowerCase() };
}
