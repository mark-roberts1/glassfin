import { Jellyfin } from './jellyfin';

let client = $state<Jellyfin | null>(Jellyfin.stored());

export const session = {
  get client(): Jellyfin | null {
    return client;
  },
  get signedIn(): boolean {
    return client !== null;
  },
  signIn(next: Jellyfin): void {
    client = next;
  },
  signOut(): void {
    client?.signOut();
    client = null;
  }
};
