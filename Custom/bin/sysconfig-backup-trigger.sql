-- Trigger function to automatically backup SMS/SMTP configuration settings
-- This runs BEFORE DELETE to capture settings before _DBCleanUp removes them

CREATE OR REPLACE FUNCTION backup_sms_smtp_config()
RETURNS TRIGGER AS $$
DECLARE
    v_setting_name VARCHAR(250);
    v_setting_value TEXT;
    v_default_id INTEGER;
BEGIN
    -- Get the setting name from sysconfig_default
    IF TG_OP = 'DELETE' THEN
        SELECT name INTO v_setting_name
        FROM sysconfig_default
        WHERE id = OLD.sysconfig_default_id;

        v_setting_value := OLD.effective_value;
        v_default_id := OLD.sysconfig_default_id;
    ELSE
        SELECT name INTO v_setting_name
        FROM sysconfig_default
        WHERE id = NEW.sysconfig_default_id;

        v_setting_value := NEW.effective_value;
        v_default_id := NEW.sysconfig_default_id;
    END IF;

    -- Only backup SMS/SMTP settings
    IF v_setting_name LIKE 'SMSNotification::%' OR
       v_setting_name LIKE 'SMTPNotification::%' THEN

        -- Insert or update backup (UPSERT)
        INSERT INTO msst_config_backup (setting_name, setting_value, backup_time)
        VALUES (v_setting_name, v_setting_value, CURRENT_TIMESTAMP)
        ON CONFLICT (setting_name)
        DO UPDATE SET
            setting_value = EXCLUDED.setting_value,
            backup_time = EXCLUDED.backup_time;

        RAISE NOTICE 'MSSTLite: Backed up setting % = %', v_setting_name, v_setting_value;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS backup_sms_smtp_config_trigger ON sysconfig_modified;

-- Create trigger that fires BEFORE DELETE to capture settings before removal
CREATE TRIGGER backup_sms_smtp_config_trigger
    BEFORE INSERT OR UPDATE OR DELETE ON sysconfig_modified
    FOR EACH ROW
    EXECUTE FUNCTION backup_sms_smtp_config();

COMMENT ON FUNCTION backup_sms_smtp_config() IS
    'MSSTLite: Automatically backs up SMS/SMTP configuration settings to msst_config_backup table before they are deleted during package uninstall';
