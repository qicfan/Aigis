import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { promptAction, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OTP, OTPSchema, parseURI } from '../crypto/otpUtils'
import { CodeResponseSchema, OTPItemInfo, iconMatcher, MasterKeyInfo, SecretSchema,
    AigisContentSchema } from '../common/schema'
import { arrayRearrange, shallowCopy } from '../common/utils';
import { AIGIS_PREF_NAME, PREF_KEY_SECRETS, PREF_KEY_SETTINGS, PREF_MASTER_KEY } from '../common/conts';
import { PREF_KEY_ITEMS } from '../common/conts';
import { DefaultUserPreferences, UserPreferences, ValueType } from '../common/settings';
import { generateMasterKeyInHUKS } from '../crypto/authUtils';
import { AES_KEY_USAGE } from '../crypto/huksUtils';
import { CodeRequestSchema, EVENT_CODE_REQUEST,
    EVENT_EXPORT_REQUEST,
    EVENT_IMPORT_REQUEST,
    EVENT_MOVE_TO_TOP,
    EVENT_REMOVE_ITEM,
    EVENT_UPDATE_ITEM,
    EVENT_UPDATE_PASSWORD,
    EVENT_UPDATE_SETTING,
    FileExportRequestSchema,
    FileImportRequestSchema,
    MoveToTopRequestSchema,
    PasswordUpdateRequestSchema,
    RemovalRequestSchema,
    SettingUpdateRequestSchema,
    UpdateRequestSchema } from '../common/events';
import { AigisImporter } from '../importers/aigis';

class PreferencesManager {
    private _instances: Map<string, OTP>;
    private _secrets: SecretSchema[];
    private _items: OTPItemInfo[];

    constructor(items: OTPItemInfo[], secrets: SecretSchema[]) {
        this._items = items;
        this._secrets = secrets;
        this._instances = new Map();
    }

    get leaked_secrets() {
        return this._secrets;
    }

    get items() {
        return this._items;
    }

    getOtpInstance(keyAlias: string): OTP {
        let otp = this._instances.get(keyAlias);
        if (otp===undefined) {
            const schema = this._items.find(x => x.keyAlias===keyAlias)?.schema;
            const secret = this._secrets.find(x => x.keyAlias===keyAlias)?.secret;
            if (schema===undefined) {
                throw Error(`"${keyAlias}" not found in local manager.`);
            }
            //
            let schema_tmp = shallowCopy(schema) as OTPSchema;
            schema_tmp.secret = secret;
            otp = OTP.fromSchema(schema_tmp);
        }
        return otp;
    }

    async requestCodeUpdate(keyAlias: string): Promise<boolean> {
        const item = this._items.find(x => x.keyAlias===keyAlias);
        if (item) {
            const otp = this.getOtpInstance(keyAlias);
            item.code = {
                timestamp: Date.now(),
                code: await otp.generateOTP(),
            }
            return true;
        } else {
            return false;
        }
    }

    updatePreferenceItem(uri: string, oldKeyAlias?: string) {
        const args = parseURI(uri);
        const otp = OTP.fromArguments(args);
        const secret = args.get('secret');

        const newKeyAlias = oldKeyAlias===undefined ? (otp as OTP).keyAlias : oldKeyAlias;
        const oldItem = this._items.find(x => oldKeyAlias===x.keyAlias);
        const oldSecret = this._secrets.find(x => oldKeyAlias===x.keyAlias);

        if (oldItem!==undefined) {
            const oldKeyAlias = oldItem.keyAlias;
            oldItem.keyAlias = newKeyAlias;
            oldItem.icon = iconMatcher(otp.schema.issuer);
            //
            oldItem.schema = otp.schema;
            if (secret && oldSecret) { oldSecret.secret = secret; }
            // update new instances
            this._instances.delete(oldKeyAlias);
            this.requestCodeUpdate(newKeyAlias);
        } else {
            this.appendPreferenceItem(otp, secret!);
        }
    }

    private appendPreferenceItem(otp: OTP, secret: string) {
        const keyAlias = otp.keyAlias;
        const schema = otp.schema;

        // find issuer icon
        const icon = iconMatcher(otp.schema.issuer);
        const code: CodeResponseSchema = {timestamp:0, code:'000000'};
        this._items.push({keyAlias, icon, code, schema});
        this._secrets.push({keyAlias, secret});
        this._instances.set(keyAlias, this.getOtpInstance(keyAlias));
    }

    removePreferenceItem(keyAlias: string) {
        //
        const itemIndex = this._items.findIndex(x => x.keyAlias===keyAlias);
        this._items.splice(itemIndex, 1);
        //
        const secretIndex = this._secrets.findIndex(x => x.keyAlias===keyAlias);
        this._secrets.splice(secretIndex, 1);
        //
        this._instances.delete(keyAlias);
    }

    insertPreferenceItem(keyAlias1: string, keyAlias2?: string) {
        //
        const keyItem1 = this._items.findIndex(x => x.keyAlias===keyAlias1);
        const keyItem2 = keyAlias2 ? this._items.findIndex(x => x.keyAlias===keyAlias2) : 0;
        arrayRearrange(this._items, keyItem1, keyItem2);
        //
        const keySecret1 = this._items.findIndex(x => x.keyAlias===keyAlias1);
        const keySecret2 = keyAlias2 ? this._items.findIndex(x => x.keyAlias===keyAlias2) : 0;
        arrayRearrange(this._secrets, keySecret1, keySecret2);
    }

    persists(dataPreferences: preferences.Preferences) {
        dataPreferences!.putSync(PREF_KEY_ITEMS, this._items);
        dataPreferences!.putSync(PREF_KEY_SECRETS, this._secrets);
        dataPreferences!.flush();
    }
}

export default class EntryAbility extends UIAbility {
    private dataPreferences?: preferences.Preferences;
    private localStorage: LocalStorage = new LocalStorage();
    private instPreferences?: PreferencesManager;
    private localSettings?: UserPreferences;
    private masterKeyInfo?: MasterKeyInfo;

    onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    }

    onDestroy(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    }

    onWindowStageCreate(windowStage: window.WindowStage): void {
        // set main window in privacy mode
        const mainWindow = windowStage.getMainWindowSync();
        mainWindow.setWindowPrivacyMode(true);
        mainWindow.on('avoidAreaChange', (data) => {
            if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
                let topRectHeight = data.area.topRect.height;
                AppStorage.setOrCreate('topRectHeight', topRectHeight);
            } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
                let bottomRectHeight = data.area.bottomRect.height;
                AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
            }
        });

        preferences.getPreferences(this.context, AIGIS_PREF_NAME)
            .then((pref: preferences.Preferences) => {
                this.dataPreferences = pref;
                // init
                this.instPreferences = new PreferencesManager(
                  this.dataPreferences.getSync(PREF_KEY_ITEMS, []) as OTPItemInfo[],
                  this.dataPreferences.getSync(PREF_KEY_SECRETS, []) as SecretSchema[],
                );
                this.localStorage.setAndProp(PREF_KEY_ITEMS, this.instPreferences.items);
                // setup global user settings
                this.initUserPreferences(pref);
                // register event handler
                this.registerEventHubHandlers();

                // init index page
                windowStage.loadContent('pages/Index', this.localStorage);
            })
            .catch((err: BusinessError) => {
                console.error("Failed to get preferences. code =" + err.code + ", message =" + err.message);
            });
    }

    onWindowStageDestroy(): void {
        // Main window is destroyed, release UI related resources
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
        this.context.eventHub.off(EVENT_CODE_REQUEST);
    }

    onForeground(): void {
        // Ability has brought to foreground
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    }

    onBackground(): void {
        // Ability has back to background
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
    }

    private initUserPreferences(pref: preferences.Preferences) {
        // try to load user settings
        const settingString = pref.getSync(PREF_KEY_SETTINGS, '[]') as string;
        const settingItems  = JSON.parse(settingString) as [string, ValueType][];
        this.localSettings = new Map(settingItems);
        for (const obj of DefaultUserPreferences.entries()) {
            const key = obj[0], defaultValue = obj[1];
            const localValue = this.localSettings.get(key);
            if (localValue===undefined) {
                AppStorage.setAndProp(`settings${key}`, defaultValue);
            } else {
                AppStorage.setAndProp(`settings${key}`, localValue);
            }
        }

        // try to load master key
        this.masterKeyInfo = pref.getSync(PREF_MASTER_KEY, {}) as MasterKeyInfo;
        AppStorage.setAndProp('MasterKeyAvailable', this.masterKeyInfo.keyAlias!==undefined);
    }

    private registerEventHubHandlers() {
        this.context.eventHub.on(EVENT_CODE_REQUEST, async (data: CodeRequestSchema) => {
            if (this.instPreferences) {
                const res = await this.instPreferences.requestCodeUpdate(data.keyAlias);
                if (res) {
                    this.localStorage.set(PREF_KEY_ITEMS, this.instPreferences.items);
                }
            }
        });
        this.context.eventHub.on(EVENT_UPDATE_ITEM, (data: UpdateRequestSchema) => {
            if (this.instPreferences) {
                // update local preferences
                this.instPreferences.updatePreferenceItem(data.uri, data.keyAlias);
                // update persist preferences
                this.instPreferences.persists(this.dataPreferences!);
                // propagate updated items
                this.localStorage.set(PREF_KEY_ITEMS, this.instPreferences.items);
            }
        });
        this.context.eventHub.on(EVENT_MOVE_TO_TOP, (data: MoveToTopRequestSchema) => {
            if (this.instPreferences) {
                // swap in local preferences
                this.instPreferences.insertPreferenceItem(data.keyAlias);
                // update persist preferences
                this.instPreferences.persists(this.dataPreferences!);
                // propagate updated items
                this.localStorage.set(PREF_KEY_ITEMS, this.instPreferences.items);
            }
        });
        this.context.eventHub.on(EVENT_REMOVE_ITEM, (data: RemovalRequestSchema) => {
            if (this.instPreferences) {
                // removal in local preferences
                this.instPreferences.removePreferenceItem(data.keyAlias);
                // update persist preferences
                this.instPreferences.persists(this.dataPreferences!);
                // propagate updated items
                this.localStorage.set(PREF_KEY_ITEMS, this.instPreferences.items);
            }
        });
        this.context.eventHub.on(EVENT_UPDATE_SETTING, (data: SettingUpdateRequestSchema) => {
            if (this.localSettings) {
                this.localSettings.set(data.key, data.value);
                AppStorage.set(`settings${data.key}`, data.value);
                //
                const settingItems = Array.from( this.localSettings.entries() );
                const settingString = JSON.stringify(settingItems);
                this.dataPreferences?.putSync(PREF_KEY_SETTINGS, settingString);
                this.dataPreferences?.flush();
            }
        });
        this.context.eventHub.on(EVENT_UPDATE_PASSWORD, async (data: PasswordUpdateRequestSchema) => {
            if (this.dataPreferences) {
                const keyAlias = PREF_MASTER_KEY;
                const masterKeyInfo = await generateMasterKeyInHUKS(keyAlias, data.password, AES_KEY_USAGE.ENCRYPT);
                this.masterKeyInfo = masterKeyInfo;
                //
                this.dataPreferences?.putSync(PREF_MASTER_KEY, masterKeyInfo);
                this.dataPreferences?.flush();
                AppStorage.set('MasterKeyAvailable', true);
            }
        });
        this.context.eventHub.on(EVENT_EXPORT_REQUEST, async (data: FileExportRequestSchema) => {
            if (this.masterKeyInfo===undefined || this.instPreferences===undefined) {
                return;
            }

            try {
                const settingString = this.localSettings? JSON.stringify(Array.from( this.localSettings.entries() )) : undefined;
                //
                const file = await fs.open(data.uri, fs.OpenMode.CREATE|fs.OpenMode.WRITE_ONLY);
                const content: AigisContentSchema = {
                    masterKey: this.masterKeyInfo,
                    items: this.instPreferences.items,
                    secrets: this.instPreferences.leaked_secrets,
                    settings: settingString,
                };
                const result = await (new AigisImporter()).save(file.fd, this.masterKeyInfo.keyAlias, content);
                if (result) {
                    promptAction.showToast({message: `Export to ${data.uri}`});
                } else {
                    promptAction.showToast({message: 'Export failed.'});
                    throw Error('Export failed.');
                }
            } catch (err) {
                fs.unlink(data.uri);
            }
        });
        this.context.eventHub.on(EVENT_IMPORT_REQUEST, async (data: FileImportRequestSchema) => {
            const file = await fs.open(data.uri, fs.OpenMode.READ_ONLY);
            const content = await (new AigisImporter()).load(file.fd, data.password!);
            console.log('success')
        })
    }
}
