import { ValueType } from "./settings";

export const EVENT_CODE_REQUEST: string = 'code-request';
export interface CodeRequestSchema {
    keyAlias: string,
}


export const EVENT_UPDATE_ITEM: string = 'update-item';
export interface UpdateRequestSchema {
    uri: string,
    keyAlias?: string,
}
export interface UpdateResponseSchema {
    success: boolean,
    message?: string,
}

export const EVENT_MOVE_TO_TOP: string = 'move-to-top';
export interface MoveToTopRequestSchema {
    keyAlias: string,
}

export const EVENT_REMOVE_ITEM: string = 'remove-item';
export interface RemovalRequestSchema {
    keyAlias: string,
}

export const EVENT_UPDATE_SETTING: string = 'update-setting';
export interface SettingUpdateRequestSchema {
    key: string,
    value: ValueType,
}

export const EVENT_UPDATE_PASSWORD: string = 'update-password';
export interface PasswordUpdateRequestSchema {
    password: string,
}

export const EVENT_EXPORT_REQUEST: string = 'export-request';
export interface FileExportRequestSchema {
    format: string,
    uri: string,
}

export const EVENT_IMPORT_REQUEST: string = 'import-request';
export interface FileImportRequestSchema {
    format: string,
    uri: string,
    password?: string,
}
