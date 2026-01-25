export type KnownValidator = {
  /** Short CLI key, lowercase, no spaces. */
  key: string;
  /** Human label shown in `validators` output. */
  label: string;
  /** Canton party id. */
  party: string;
};

// Curated list for convenience.
// Extend this list as needed (or add a generator later).
export const KNOWN_VALIDATORS: KnownValidator[] = [
  {
    key: "arkhia",
    label: "Arkhia Validator 1",
    party: "Arkhia-Validator-1::12208f49e6bc2638dc72b1fc7a5cda5380fad110b90c1dbc409296948f14052b2b9e",
  },
  {
    key: "fna",
    label: "FNA Validator 1",
    party: "FNA-validator-1::12209428025ce1055074f26ae3cdca82d359a8cb4a7d3fcfa5b64c8140b3d17e2bf5",
  },
  {
    key: "7ridge-1",
    label: "7Ridge Validator 1",
    party: "7Ridge-validator-1::12204814f21ba340ac90d654133a97300a1cb543e0ac8573fe5fa5228fe61522e0ac",
  },
  {
    key: "7ridge-2",
    label: "7Ridge Validator 2",
    party: "7Ridge-validator-2::1220f1584f579e9be2205df88bd40ed18b47d5166f191be284e74a66e6f6ea0da6f2",
  },
];

export function resolveValidatorParty(key: string): string {
  const normalized = key.trim().toLowerCase();
  const hit = KNOWN_VALIDATORS.find((v) => v.key === normalized);
  if (!hit) {
    const known = KNOWN_VALIDATORS.map((v) => v.key).sort().join(", ");
    throw new Error(`Unknown validator key: ${key}. Known: ${known || "(none)"}`);
  }
  return hit.party;
}
