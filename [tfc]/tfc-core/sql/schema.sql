-- The Final Core schema. tfc-core runs this automatically on start;
-- every statement is idempotent (IF NOT EXISTS), so re-running is safe.
-- Statements are separated by a semicolon at the end of a line.

CREATE TABLE IF NOT EXISTS `tfc_users` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `license`    VARCHAR(64)  NOT NULL,
    `name`       VARCHAR(64)  NULL,
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_tfc_users_license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Every linked identifier a user has connected with (discord, fivem).
-- Keeps history: the same Discord seen on two licenses shows up as two rows.
CREATE TABLE IF NOT EXISTS `tfc_user_identifiers` (
    `user_id`    INT UNSIGNED NOT NULL,
    `type`       VARCHAR(16)  NOT NULL,
    `value`      VARCHAR(64)  NOT NULL,
    `first_seen` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `type`, `value`),
    KEY `idx_tfc_user_identifiers_lookup` (`type`, `value`),
    CONSTRAINT `fk_tfc_user_identifiers_user` FOREIGN KEY (`user_id`) REFERENCES `tfc_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `tfc_characters` (
    `id`          INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    `cid`         CHAR(8)          NOT NULL,
    `user_id`     INT UNSIGNED     NOT NULL,
    `slot`        TINYINT UNSIGNED NOT NULL,
    `firstname`   VARCHAR(32)      NOT NULL,
    `lastname`    VARCHAR(32)      NOT NULL,
    `dob`         DATE             NULL,
    `sex`         CHAR(1)          NULL,
    `position`    TEXT             NULL,
    `metadata`    LONGTEXT         NULL,
    `created_at`  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_played` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_tfc_characters_cid` (`cid`),
    UNIQUE KEY `uq_tfc_characters_slot` (`user_id`, `slot`),
    CONSTRAINT `fk_tfc_characters_user` FOREIGN KEY (`user_id`) REFERENCES `tfc_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
