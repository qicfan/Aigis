import { OTPSchema } from "../crypto/otpUtils";
import { UserPreferences } from "./settings";

interface IssuerName {
    issuer: string,
    name: string
}

export function name2keyAlias(props: IssuerName): string {
    return `${props.issuer}:${props.name}`;
}

export function iconMatcher(issuer: string): string {
    const issuerKey = issuer.toLowerCase().replace(/(\.org|\.com)$/, '')
    return `icons/issuers/${issuerKey}.svg`;
}

export interface CodeResponseSchema {
    timestamp: number,
    code: string,
}

export interface OTPItemInfo {
    keyAlias: string,
    icon: string,
    code: CodeResponseSchema,
    schema: OTPSchema,
}

export interface SecretSchema {
    keyAlias: string,
    secret: string,
    encrypted?: boolean,
}

export interface AigisContentSchema {
    masterKey: MasterKeyInfo,
    items: OTPItemInfo[],
    secrets: SecretSchema[],
    settings?: string,
}

export interface PBKDF2Material {
    salt: Uint8Array,
    iteration: number,
}
export interface MasterKeyInfo {
    type: 'PBKDF2',
    version: 'v1',
    keyAlias: string,
    secret: PBKDF2Material,
    params: PBKDF2Material,
}

export interface AesGcmMaterial {
    aad: Uint8Array,
    nonce: Uint8Array,
}
