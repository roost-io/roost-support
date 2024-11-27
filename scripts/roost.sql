-- -----------------------------------------------------
-- MySQL Roost Schema
-- It contains all tables and views
-- Used by Nest JS to apply schema
-- -----------------------------------------------------


-- -----------------------------------------------------
-- These variables allow schema addition without 
-- checking for FOREIGN KEY restriction
-- -----------------------------------------------------
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- -----------------------------------------------------
-- Table `company`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `company` (
  `id` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT NULL,
  `is_active` SMALLINT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `name_UNIQUE` (`name` ASC) 
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user` (
  `id` VARCHAR(100) NOT NULL,
  `username` VARCHAR(255) NOT NULL,
  `company_id` VARCHAR(100) NULL,
  `company_name` VARCHAR(100) NULL,
  `role_ids` VARCHAR(500) NULL,
  `first_name` VARCHAR(100) NULL DEFAULT NULL,
  `last_name` VARCHAR(100) NULL DEFAULT NULL,
  `email` VARCHAR(255) NULL,
  `email_hash` VARCHAR(255) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT NULL,
  `is_active` SMALLINT NULL DEFAULT 1,
  `location` VARCHAR(500) NULL,
  `avatar_url` VARCHAR(4000) NULL,
  `roost_sessions` VARCHAR(255) NULL,
  `resident_since` CHAR(4) NULL,
  `bio` VARCHAR(255) NULL,
  `certifications` VARCHAR(255) NULL,
  `total_services` VARCHAR(255) NULL,
  `linkedin_url` VARCHAR(255) NULL,
  `twitter_url` VARCHAR(255) NULL,
  `full_name` VARCHAR(100) NULL DEFAULT NULL,
  `referrer_url` VARCHAR(500) DEFAULT NULL,
  `env_config` TEXT NULL,
  `notif_count` INT NOT NULL DEFAULT 0,
  `is_super_admin` SMALLINT NULL DEFAULT 0,
  `send_telemetry_data` SMALLINT NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `username_UNIQUE` (`username` ASC),
  CONSTRAINT `company`
    FOREIGN KEY (`company_id`)
    REFERENCES `company` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `login_status`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `login_status` (
  `id` VARCHAR(100) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `sign_in_time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sign_out_time` TIMESTAMP NULL DEFAULT NULL,
  `device_type` VARCHAR(500) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `userid_idx` (`user_id` ASC),
  CONSTRAINT `userid`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `role`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `role` (
  `id` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `created_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

insert ignore into role (id, name) values ('cloud-native-developer', 'Cloud Native Developer');
insert ignore into role (id, name) values ('cloud-native-executive', 'Cloud Native Executive');
insert ignore into role (id, name) values ('cloud-native-investor', 'Cloud Native Investor');
insert ignore into role (id, name) values ('cloud-native-evangelist', 'Cloud Native Evangelist');
insert ignore into role (id, name) values ('partner-admin', 'Partner Admin');
insert ignore into role (id, name) values ('devops-write', 'DevOps Admin');
insert ignore into role (id, name) values ('devops-read', 'DevOps View');

-- -----------------------------------------------------
-- Table `user_role`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_role` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `role_id` VARCHAR(100) NOT NULL,
  `created_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`user_id`, `role_id`),
  CONSTRAINT `fk_user_role_user_id_2`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `fk_user_role_role_id_2`
    FOREIGN KEY (`role_id`)
    REFERENCES `role` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `thirdparty_login`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `thirdparty_login` (
  `id` VARCHAR(100) NOT NULL,
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT NULL,
  `app_username` VARCHAR(255) NULL,
  `app_user_id` VARCHAR(255) NULL,
  `addtional_params_json` VARCHAR(500) NULL,
  `devops_role` ENUM("read", "write", "none") DEFAULT "none",
  `is_client_admin` SMALLINT NULL DEFAULT 0,
  `is_active` SMALLINT NULL DEFAULT 1,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `gpt_settings` TEXT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `connect_request`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `connect_request` (
  `id` VARCHAR(100) NOT NULL,
  `from_user_id` VARCHAR(100) NOT NULL,
  `to_user_id` VARCHAR(100) NOT NULL,
  `requested_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `approval_status` SMALLINT NULL DEFAULT 0,
  `subject` VARCHAR(255) NULL,
  `description` VARCHAR(500) NULL,
  `modified_on` TIMESTAMP NULL,
  `access_key` VARCHAR(200) NULL,
  `expires_on` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `user_from`
    FOREIGN KEY (`from_user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `user_to`
    FOREIGN KEY (`to_user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_device`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_device` (
  `id` VARCHAR(100) NOT NULL,
  `mac_id` VARCHAR(100) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `device_key` VARCHAR(100) NULL,
  `platform` VARCHAR(100) NULL,
  `arch` VARCHAR(100) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `inactive` SMALLINT NULL,
  `device_name` VARCHAR(100) NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `mac_id_UNIQUE` (`mac_id` ASC)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `app_user_token`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `app_user_token` (
  `id` INT(10) NOT NULL AUTO_INCREMENT,
  `user_id` VARCHAR(100) NOT NULL,
  `app_user_id` VARCHAR(255) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active` SMALLINT NULL DEFAULT 0,
  `customer_email` VARCHAR(255) NULL,
  `customer_token` VARCHAR(500) NULL,
  `mac_id` VARCHAR(45) NULL,
  `alias` VARCHAR(200) NULL,
  `node_username` VARCHAR(100) NULL,
  `num_nodes` INT NOT NULL DEFAULT 1,
  `public_ip` VARCHAR(50) NULL,
  `worker_ip` VARCHAR(1000) NULL,
  `private_key` TEXT NULL,
  `kubeconfig` TEXT NULL,
  `roostapi_key` VARCHAR(255) NULL,
  `cluster_state` TEXT NULL,
  `running_on` TIMESTAMP NULL,
  `stopped_on` TIMESTAMP NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `app_manifest` TEXT NULL,
  `failure_message` VARCHAR(256) NULL,
  `failure_details` TEXT NULL,
  `status_message` VARCHAR(100) NULL,
  `jumphost_id` VARCHAR(45) NULL,
  `vendor` VARCHAR(10) NULL,
  `is_heterogenous` SMALLINT NULL DEFAULT 0,
  `nodes_config` TEXT NULL,
  `docker_daemon` VARCHAR(50) NULL,
  `docker_registry` VARCHAR(50) NULL,
  `collaboration_enabled` SMALLINT NULL DEFAULT 1,
  `autodeploy` SMALLINT NULL DEFAULT 0,
  `allow_root_containers` SMALLINT NULL DEFAULT 1,
  `roost_cluster` SMALLINT NULL DEFAULT 1,
  `plugins` VARCHAR(2000) NULL DEFAULT '{"argo":false,"falco":false,"istio":false,"linkerd":false,"airflow":false,"servicemesh":{"enabled":false,"request_rate":20,"error_rate":10,"latency":5000,"saturation":50,"interval_time":1},"slack":{"enabled":false,"channel":"","token":""}}',
  `random_tag_docker_build` SMALLINT NULL DEFAULT 0,
  `started_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `env_config` TEXT NULL,
  `gotty_port` TEXT NULL,
  `cluster_type` ENUM("roost", "managed") DEFAULT "roost",
  `cluster_cost` FLOAT NULL DEFAULT 0,
  `cluster_team_config` TEXT NULL,
  `env_type` ENUM("k8s", "docker") DEFAULT "k8s",
  `use_admin_creds` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_activity`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_activity` (
  `id` VARCHAR(100) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `device_id` VARCHAR(100) NOT NULL,
  `activity_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `activity_type` VARCHAR(10) NULL,
  `name` VARCHAR(500) NULL,
  `file_size_kb` BIGINT NULL,
  `status` VARCHAR(50) NULL,
  `namespace` VARCHAR(200) NULL,
  `transfer_transaction_id` VARCHAR(200) NOT NULL,
  `additional_params_json` VARCHAR(2000) NULL,
  `to_user_id` VARCHAR(100) NULL,
  `change_status` VARCHAR(50) NULL,
  `checksum` VARCHAR(100) NULL,
  `message` TEXT NULL,
  `gitops_user` VARCHAR(100) NULL,
  `git_branch` VARCHAR(255) NULL,
  `git_repo` VARCHAR(200) NULL,
  `gitops_at` TIMESTAMP NULL,
  `gitops_device_id` VARCHAR(100) NULL,
  `build_activity_pk` VARCHAR(45) NULL,
  `cluster_id` INT NULL,
  `team_transaction_id` VARCHAR(200) NULL,
  `filepath` VARCHAR(500) NULL,
  `to_device_id` VARCHAR(100) NULL,
  INDEX `useract_idx` (`user_id` ASC),
  INDEX `collaboration_id` (`transfer_transaction_id` ASC),
  PRIMARY KEY (`id`),
  CONSTRAINT `useract`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
 CONSTRAINT `useracttto`
    FOREIGN KEY (`to_user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `user_activity_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `services`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `services` (
  `collaboration_id` VARCHAR(200) NOT NULL,
  `artifact_name` VARCHAR(200) NOT NULL,
  `svc_name` VARCHAR(200) NOT NULL,
  `test_details` TEXT NULL,
  `test_status` ENUM("PASS", "FAIL") NULL,
  `updated_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `test_comments` VARCHAR(3000) NULL,
  `test_type` VARCHAR(200) NULL,
  `test_output_json` TEXT NULL,
  PRIMARY KEY (`collaboration_id`, `artifact_name`, `svc_name`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_build_activity`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_build_activity` (
  `id` VARCHAR(45) NOT NULL,
  `build_id` VARCHAR(11) NULL,
  `user_id` VARCHAR(45) NULL,
  `activity_type` VARCHAR(30) NULL,
  `artifact_name` VARCHAR(500) NOT NULL,
  `file_name` VARCHAR(500) NULL,
  `namespace` VARCHAR(50) NULL,
  `checksum` VARCHAR(65) NULL,
  `git_log` TEXT NULL,
  `git_patch` TEXT NULL,
  `artifact_built_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `mac_id` VARCHAR(45) NOT NULL,
  `cluster_alias` VARCHAR(200) NULL,
  `cluster_id` INT(10) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `certified_artifact`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `certified_artifact` (
  `id` VARCHAR(45) NOT NULL,
  `id_type` ENUM("collaboration_id", "build_id") DEFAULT "collaboration_id",
  `certify_id` VARCHAR(200) NOT NULL,
  `mac_id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NULL,
  `certified_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `certify_message` VARCHAR(300) NULL,
  `status` SMALLINT NULL DEFAULT 1,
  `cluster` VARCHAR(100) NULL,
  `docker_host` VARCHAR(100) NULL,
  `test_case_url` VARCHAR(300) NULL,
  `test_result_url` VARCHAR(300) NULL,
  `git_repo` VARCHAR(300) NULL,
  `git_branch` VARCHAR(255) NULL,
  `certification_mode` ENUM('manual', 'auto') NULL DEFAULT 'manual',
  `lkg` VARCHAR(30) NULL,
  `lkg_time` TIMESTAMP NULL,
  `cluster_id` INT(10) NULL,
  `clusterconfig` TEXT NULL,
  `certify_state` VARCHAR(45) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `vulnerability_runtime_events`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `vulnerability_runtime_events` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `mac_id` VARCHAR(45) NOT NULL,
  `reported_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `event_type` ENUM("Vulnerability", "Security Event") NOT NULL,
  `severity` ENUM("Critical", "High", "Medium", "Low", "Unknown", "Error", "Warning", "Notice") NOT NULL,
  `event_details` VARCHAR(500) NULL,
  `image` VARCHAR(200) NULL,
  `cluster_alias` VARCHAR(200) NULL,
  `cluster_id` INT NULL,
  `cve_url` VARCHAR(500) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `app_activity`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `app_activity` (
  `id` VARCHAR(100) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `device_id` VARCHAR(100) NULL,
  `activity_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `activity_type` VARCHAR(50) NULL,
  `host_name` VARCHAR(500) NULL,
  `public_ip` CHAR(15) NULL,
  `customer_email` VARCHAR(255) NULL,
  `customer_token` VARCHAR(500) NULL,
  `additional_params_json` VARCHAR(2000) NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `appuser`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `project_info`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `project_info` (
  `id` INT(10) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(200) NOT NULL,
  `status` ENUM('Submitted','Accepted','Rejected') DEFAULT NULL,
  `repo_url` VARCHAR(500) NOT NULL,
  `description` TEXT NOT NULL,
  `collab_used` SMALLINT DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `repo_url_unique` (`repo_url` ASC)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `project_user`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `project_user` (
  `username` VARCHAR(50) NOT NULL,
  `project_id` INT(10)  NOT NULL,
  PRIMARY KEY (`username`,`project_id`),
  CONSTRAINT `fk_project_user_username`
    FOREIGN KEY (`username`)
    REFERENCES `user` (`username`),
  CONSTRAINT `fk_project_user_project_id`
    FOREIGN KEY (`project_id`)
    REFERENCES `project_info` (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `roost_activity`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `roost_activity` (
  `id` VARCHAR(36) NOT NULL,
  `user_id` VARCHAR(36) NULL,
  `device_id` VARCHAR(36) NOT NULL,
  `team_id` VARCHAR(36) NULL,
  `type` VARCHAR(50) NOT NULL,
  `component` VARCHAR(100) NOT NULL,
  `activity` TEXT NULL,
  `activity_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `public_ip` VARCHAR(16) NULL,
  `version` VARCHAR(16) NULL,
  `platform` VARCHAR(20) NULL,
  `category` ENUM(
      'Collaborate',
      'Deploy',
      'DockerBuild',
      'SignIn',
      'TeamSignIn',
      'ClusterSwitch',
      'SignOut',
      'Code'
    ) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Table `org` for team
-- ----------------
CREATE TABLE IF NOT EXISTS `org` (
  `org` VARCHAR(20),
  `email_domain` VARCHAR(36),
  PRIMARY KEY (`org`, `email_domain`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Table `team`
-- ----------------
CREATE TABLE IF NOT EXISTS `team` (
  `id` VARCHAR(36) NOT NULL,
  `created_by` VARCHAR(36)  NOT NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `name` VARCHAR(200) NOT NULL,
  `description` TEXT NULL,
  `visibility` ENUM("public", "private", "organization") DEFAULT "public",
  `is_auto_sync` SMALLINT NULL DEFAULT 1,
  `org` VARCHAR(20) NULL,
  `config` TEXT NULL,
  `team_ns_regex` TEXT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `name_UNIQUE` (`name` ASC),
  CONSTRAINT `team_created_by_fk`
    FOREIGN KEY (`created_by`)
    REFERENCES  `user` (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Table `team_members`
-- ----------------
CREATE TABLE IF NOT EXISTS `team_members` (
  `team_id` varchar(36) not null,
  `member_id` varchar(36) not null, -- can be user_id or team_id
  `member_type` ENUM("user", "team"),
  `member_role` ENUM("read-only", "read-write"),
  `joining_date` timestamp not null default current_timestamp,
  `is_admin` SMALLINT NULL DEFAULT 0,
  `made_admin_on` timestamp null,
  `namespace_regex` VARCHAR(255) NOT NULL DEFAULT '',
  `namespace_role` ENUM("read-only", "read-write") NOT NULL DEFAULT "read-only",
  PRIMARY KEY (`team_id`, `member_id`),
  CONSTRAINT `team_members_team_id_fk`
    FOREIGN KEY (`team_id`)
    REFERENCES `team` (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Table `team_join_requests`
-- ----------------
CREATE TABLE IF NOT EXISTS `team_join_requests` (
  `team_id` varchar(36) not null,
  `member_id` varchar(36) not null,
  `status`  SMALLINT not null default 0,
  `requested_on` timestamp not null default current_timestamp,
  `responded_on` timestamp null,
  PRIMARY KEY (`team_id`, `member_id`),
  CONSTRAINT `team_join_requests_team_id_fk`
    FOREIGN KEY (`team_id`)
    REFERENCES `team` (`id`),
  CONSTRAINT `team_join_requests_user_id_fk`
    FOREIGN KEY (`member_id`)
    REFERENCES `user` (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Table `team_join_invites`
-- ----------------
CREATE TABLE IF NOT EXISTS `team_join_invites` (
  `team_id` varchar(36) not null,
  `member_id` varchar(36) not null, -- can be user_id or team_id
  `status`  SMALLINT not null default 0,
  `requested_on` timestamp not null default current_timestamp,
  `responded_on` timestamp null,
  PRIMARY KEY (`team_id`, `member_id`),
  CONSTRAINT `team_invitations_team_id_fk`
    FOREIGN KEY (`team_id`)
    REFERENCES `team` (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -------------------
-- Mapping between team_id and cluster_id
-- -------------------
CREATE TABLE IF NOT EXISTS `team_cluster` (
  `cluster_id` INT NOT NULL,
  `team_id` VARCHAR(45) NOT NULL,
  `rbac_scope` ENUM("admin", "namespace") NULL DEFAULT 'admin',
  `aws_credentials` TEXT NULL,
  PRIMARY KEY (`cluster_id`, `team_id`),
  CONSTRAINT `team_cluster_team_id_fk`
    FOREIGN KEY (`team_id`)
    REFERENCES `team` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `team_cluster_app_user_token_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- List of thirdparty_app_id which can request for a temp. (tufin) cluster
-- Cluster from these ids will always be considered temp.
-- ----------------
CREATE TABLE IF NOT EXISTS `temp_cluster_app_id` (
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  PRIMARY KEY (`thirdparty_app_id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- ----------------
-- Logos of teams to show in roost.io homepage
-- ----------------
CREATE TABLE IF NOT EXISTS `company_logos` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `company_name` VARCHAR(100) NULL,
  `image_url` VARCHAR(500) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `company_name_UNIQUE` (`company_name`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

INSERT IGNORE INTO `company_logos` (`company_name`, `image_url`) 
  VALUES 
  ('Cisco', 'assets/img/brands/cisco-logo.svg'),
  ('Tuning Bill', 'assets/img/brands/tuningbill.png'),
  ('Tufin','assets/img/brands/Tufin_logo.svg'),
  ('NetApp','assets/img/brands/netapp-logo.svg'),
  ('Akamai', 'assets/img/brands/Akamai_logo.svg'),
  ('Goldman Sachs', 'assets/img/brands/Goldman_Sachs.svg'),
  ('JP Morgan Chase & Co.','assets/img/brands/JPMorgan_Chase-Logo.svg'),
  ('NEC','assets/img/brands/NEC_logo.svg'),
  ('Wipro', 'assets/img/brands/Wipro_logo.png'),
  ('INTLFCSTONE', 'assets/img/brands/INTL_FCStone_logo.png'),
  ('Alshaya', 'assets/img/brands/Alshaya_logo.png'),
  ('Amazon', 'assets/img/brands/Amazon_logo.png'),
  ('Arcesium', 'assets/img/brands/Arcesium_logo.png'),
  ('Capgemini', 'assets/img/brands/Capgemini_logo.png'),
  ('Copods', 'assets/img/brands/copods_logo.png'),
  ('Deutsche Bank', 'assets/img/brands/Deutsche_Bank_logo.png'),
  ('Google', 'assets/img/brands/Google_logo.png'),
  ('Numerator', 'assets/img/brands/Numerator_logo.png'),
  ('Paytm', 'assets/img/brands/paytm_logo.png'),
  ('Globant', 'assets/img/brands/Globant_logo.png'),
  ('Tata Consultancy Services', 'assets/img/brands/TCS_logo.png');

-- ----------------
-- Table `roost_demo_reqs`
-- ----------------
CREATE TABLE IF NOT EXISTS `roost_demo_reqs` (
  `id` VARCHAR(36) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `name` VARCHAR(100) NULL,
  `company_name` VARCHAR(100) NULL,
  `preferred_timezone` VARCHAR(50) NULL,
  `requested_on` timestamp not null default current_timestamp,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- View `user_view`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_view AS
  select 0 as view_priority, user.*
    from user inner join company on company.id = user.company_id
    where company.name not in ('InfoObjects Inc', 'Zettabytes')
  UNION
  select 1 as view_priority, user.* 
    from user left join company on company.id = user.company_id
    where company.name is NULL
  UNION
  select 2 as view_priority, user.*
    from user inner join company on company.id = user.company_id
    where company.name  in ('InfoObjects Inc', 'Zettabytes');

-- -----------------------------------------------------
-- View `user_search_view`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_search_view 
  (id, username, first_name, last_name, email, location, avatar_url, company_name, role_ids) AS
    SELECT DISTINCT
      user.id,
      user.username,
      user.first_name,
      user.last_name,
      user.email,
      user.location,
      user.avatar_url,
      company.name AS company_name,
      userRoles.role_ids
    FROM user
      LEFT JOIN company
      ON user.company_id = company.id
      LEFT JOIN (SELECT user_id, GROUP_CONCAT(role_id, '' SEPARATOR ',') AS role_ids FROM user_role GROUP BY user_id) userRoles
      ON user.id = userRoles.user_id
    WHERE
      user.is_active = 1;

-- -----------------------------------------------------
-- View `user_request_view`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_request_view 
  (id, username, first_name, last_name, email, location, avatar_url, company_name, role_ids, to_user_id, from_user_id, approval_status, requested_on) AS
    SELECT DISTINCT
      connect_request.id,
      user.username,
      user.first_name,
      user.last_name,
      user.email,
      user.location,
      user.avatar_url,
      company.name AS company_name,
      userRoles.role_ids,
      connect_request.to_user_id,
      connect_request.from_user_id,
      connect_request.approval_status,
      connect_request.requested_on
    FROM user
      LEFT JOIN company
      ON user.company_id = company.id
      LEFT JOIN (SELECT user_id, GROUP_CONCAT(role_id, '' SEPARATOR ',') AS role_ids FROM user_role GROUP BY user_id) userRoles
      ON user.id = userRoles.user_id
		INNER JOIN connect_request
      ON user.id = connect_request.to_user_id
    WHERE
      user.is_active = 1;

-- -----------------------------------------------------
-- View `user_network_view`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_network_view 
  (id, username, first_name, last_name, email, location, avatar_url, company_name, role_ids, to_user_id, from_user_id, approval_status, requested_on) AS
    SELECT DISTINCT
      connect_request.id,
      user.username,
      user.first_name,
      user.last_name,
      user.email,
      user.location,
      user.avatar_url,
      company.name AS company_name,
      userRoles.role_ids,
      connect_request.to_user_id,
      connect_request.from_user_id,
      connect_request.approval_status,
      connect_request.requested_on
    FROM user
      LEFT JOIN company
      ON user.company_id = company.id
      LEFT JOIN (SELECT user_id, GROUP_CONCAT(role_id, '' SEPARATOR ',') AS role_ids FROM user_role GROUP BY user_id) userRoles
      ON user.id = userRoles.user_id
		INNER JOIN connect_request
      ON user.id = connect_request.from_user_id
    WHERE
      user.is_active = 1;

-- -----------------------------------------------------
-- View `user_project_view`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_project_view 
  (project_id, project_name, repo_url, status, collab_used, username, first_name, last_name, full_name, avatar_url, email, email_hash) AS 
    SELECT project_info.id,
      project_info.name,
      project_info.repo_url,
      project_info.status,
      project_info.collab_used,
      user.username,
      user.first_name,
      user.last_name,
      user.full_name,
      user.avatar_url,
      user.email,
      user.email_hash
    FROM user,
      project_info,
      project_user
    WHERE user.username = project_user.username
      AND project_user.project_id = project_info.id
    ORDER BY project_info.id DESC;

-- -----------------------------------------------------
-- View `user_device_latest`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW user_device_latest
  (id, mac_id, user_id, device_key, created_on, platform, arch, modified_on) AS
    select id, mac_id, user_id, device_key, created_on, platform, arch, max(modified_on)
    from user_device
    group by mac_id;

-- -----------------------------------------------------
-- View `yeti_connect`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW yeti_connect as
  SELECT DISTINCT u.username, u.email, u.first_name, u.last_name, tp.app_username, tp.thirdparty_app_id, tp.app_user_id, c.requested_on
  from user as u
  inner join connect_request c on u.id = c.from_user_id  and c.requested_on > '2020-11-15'
  left join thirdparty_login tp on tp.user_id = u.id
  where c.to_user_id = (select id from user where username = 'YETI')
  order by c.requested_on desc, email, app_username;

-- -----------------------------------------------------
-- View `Hack_Roosters`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW Hack_Roosters AS
  SELECT distinct u.username, u.email, u.first_name, u.last_name, tp.app_username, tp.thirdparty_app_id, tp.app_user_id
  from user as u
  left join user_activity as ua on  ua.user_id = u.id
  left join thirdparty_login tp on tp.user_id = u.id
  where ua.to_user_id = (select id from user where username = 'HACK');

-- -----------------------------------------------------
-- View `team_search_view`
-- -----------------------------------------------------
create or replace view team_search_view as
  select
    t.id,
    t.created_by,
    t.created_on,
    t.name,
    t.description,
    t.visibility,
    t.is_auto_sync,
    t.org,
    x.member_count
  from team t
  inner join (
    Select 
      team_id,
      count(team_id) as member_count
    from team_members 
    group by team_id
  ) x on x.team_id = t.id;

-- -----------------------------------------------------
-- View `v_roost_user_activity`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW `v_roost_user_activity` AS
  select  "Collaborate" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component = 'Collaborate'
  union
  select "Deploy" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component in ('kubernetes', 'helm')
    OR (component = 'docker' and activity = 'run')
  union
  select "DockerBuild" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component = 'docker' and activity != 'run'
  union
  select "SignIn" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component in ('Collaborate:team-switch', 'RoostIo')
    AND activity in ('Sign-in successfully', 'zke-cluster:signin') 
  union
  select "TeamSignIn" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component  = 'Roost Clicks'
    AND activity like 'application:team:%'
  union
  select "ClusterSwitch" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component  = 'Roost Clicks'
    AND activity like 'application:remote-cluster:%'
  union
  select "SignOut" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component in ('Collaborate:team-switch', 'Roost Quits', 'RoostIo') 
    AND activity in ('Sign-out successfully', 'IndividualId', 'app:quit')
  union
  select "Code" as category, user_id, team_id, device_id, type, component, activity, activity_on, version, platform, id
    from `roost_activity` 
    where component not in ('docker', 'kubernetes', 'helm', 'Runtime Security')
    and component not like 'Collaborate%'
    and type not like 'Vulnerability%';


-- -----------------------------------------------------
-- Table `rewards_waitlist`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `rewards_waitlist` (
  `id` VARCHAR(45) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_verified` SMALLINT NULL DEFAULT 0,
  `verified_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `email_UNIQUE` (`email` ASC)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `cluster_activity`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `cluster_activity` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `device_id` VARCHAR(100) NOT NULL,
  `cluster_id` INT NOT NULL,
  `start_time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `end_time` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  INDEX `cluster_activity_user_id_fk_idx` (`user_id` ASC),
  INDEX `cluster_activity_device_id_fk_idx` (`device_id` ASC),
  INDEX `cluster_activity_cluster_id_fk_idx` (`cluster_id` ASC),
  CONSTRAINT `cluster_activity_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `cluster_activity_device_id_fk`
    FOREIGN KEY (`device_id`)
    REFERENCES `user_device` (`mac_id`)
    ON UPDATE CASCADE,
  CONSTRAINT `cluster_activity_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `cluster_lock`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `cluster_lock` (
  `id` VARCHAR(45) NOT NULL,
  `cluster_id` INT NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `lock_start` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `lock_end` TIMESTAMP NULL,
  `unlocked_by` VARCHAR(100) NULL,
  PRIMARY KEY (`id`),
  INDEX `cluster_lock_user_id_fk_idx` (`user_id` ASC),
  INDEX `cluster_lock_unlocked_by_idx` (`unlocked_by` ASC),
  INDEX `cluster_lock_cluster_id_fk_idx` (`cluster_id` ASC),
  CONSTRAINT `cluster_lock_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `cluster_lock_unlocked_by_fk`
    FOREIGN KEY (`unlocked_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `cluster_lock_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `free_cluster`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `free_cluster` (
  `cluster_id` INT NOT NULL,
  `user_id` VARCHAR(100) NULL,
  `device_id` VARCHAR(100) NULL,
  `allocated_at` TIMESTAMP NULL,
  `end_time` TIMESTAMP NULL,
  PRIMARY KEY (`cluster_id`),
  INDEX `free_cluster_user_id_fk_idx` (`user_id` ASC),
  INDEX `free_cluster_mac_id_fk_idx` (`device_id` ASC),
  CONSTRAINT `free_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `free_cluster_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `free_cluster_mac_id_fk`
    FOREIGN KEY (`device_id`)
    REFERENCES `user_device` (`mac_id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `free_cluster_eligibile_user`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `free_cluster_eligibile_user` (
  `device_id` VARCHAR(100) NOT NULL,
  `has_received` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`device_id`),
  CONSTRAINT `free_cluster_eligible_device_id_fk`
    FOREIGN KEY (`device_id`)
    REFERENCES `user_device` (`mac_id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `roost_token`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `roost_token` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `activity_time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `activity_type` VARCHAR(100) NULL,
  `number_of_tokens` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `toost_tokens_user_id_fk_idx` (`user_id` ASC),
  CONSTRAINT `toost_tokens_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `roostio_created_cluster`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `roostio_created_cluster` (
  `id` VARCHAR(45) NOT NULL,
  `app_user_id` VARCHAR(255) NOT NULL,
  `cloud_vendor` VARCHAR(20) NOT NULL,
  `api_key` TEXT NULL,
  `customer_email` VARCHAR(255) NOT NULL,
  `customer_token` VARCHAR(500) NOT NULL,
  `config` TEXT NOT NULL,
  `requested_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_email_invite`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_email_invite` (
  `id` VARCHAR(45) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `invited_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `invitation_message` VARCHAR(5000) NULL,
  `joined_on` TIMESTAMP NULL,
  `invited_by` VARCHAR(100) NOT NULL,
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `invitee_user_id` VARCHAR(100) NULL,
  `is_invite_active` SMALLINT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  INDEX `client_email_invite_invited_by_fk_idx` (`invited_by` ASC),
  INDEX `client_email_invite_invitee_user_id_fk_idx` (`invitee_user_id` ASC),
  CONSTRAINT `client_email_invite_invited_by_fk`
    FOREIGN KEY (`invited_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `client_email_invite_invitee_user_id_fk`
    FOREIGN KEY (`invitee_user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_team`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_team` (
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `team_id` VARCHAR(36) NOT NULL,
  PRIMARY KEY (`thirdparty_app_id`),
  INDEX `client_team_team_id_fk_idx` (`team_id` ASC),
  CONSTRAINT `client_team_team_id_fk`
    FOREIGN KEY (`team_id`)
    REFERENCES `team` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `email_update_request`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `email_update_request` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `otp` VARCHAR(20) NOT NULL,
  `requested_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_valid` SMALLINT NOT NULL DEFAULT 1,
  `verified_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  INDEX `email_update_request_user_id_fk_idx` (`user_id` ASC),
  CONSTRAINT `email_update_request_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client`
-- For client specific config
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client` (
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `display_name` VARCHAR(100) NOT NULL,
  `cluster_launcher_ip` VARCHAR(100) NULL,
  `cloud_provider` VARCHAR(100) NULL,
  `email_domain` VARCHAR(100) NULL,
  `default` SMALLINT NULL DEFAULT 0,
  `show_jumphost_options` SMALLINT NULL DEFAULT 0,
  `allow_heterogeneous_cluster` SMALLINT NULL DEFAULT 0,
  `controller_deletes_cluster` SMALLINT NULL DEFAULT 0,
  `default_setting` VARCHAR(100) NULL,
  `login_expiry_hrs` INT NULL DEFAULT 168, -- 24*7 hrs
  `admin_email` TEXT NULL,
  `customer_id` VARCHAR(200) NULL,
  `source` VARCHAR(100) NULL,
  `full_name` VARCHAR(100) NULL,
  `phone_no` VARCHAR(100) NULL,
  `org_website` VARCHAR(100) NULL,
  `subscribed_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `entitlements` TEXT NULL,
  `expiry_date` DATE NULL,
  `number_of_max_clusters_allowed` INT(10) NOT NULL DEFAULT 0,
  `is_eks_enabled` SMALLINT NULL DEFAULT 0,
  `max_namespaces` INT NULL DEFAULT 2,
  `enable_eaas` SMALLINT NOT NULL DEFAULT 0,
  `enable_roost_cluster` SMALLINT NOT NULL DEFAULT 1,
  `enable_gpt` SMALLINT NOT NULL DEFAULT 1,
  `slack_token` VARCHAR(255) NULL,
  `slack_channel_name` VARCHAR(45) NULL,
  `slack_channel_id` VARCHAR(255) NULL,
  `env_config` TEXT NULL,
  `email_template` TEXT NULL,
  `installer_keys` TEXT NULL,
  `desktop_feature_flag` SMALLINT NOT NULL DEFAULT 0,
  `auto_reset_jumphost` SMALLINT NOT NULL DEFAULT 1,
  `auto_reset_ec2Launcher` SMALLINT NOT NULL DEFAULT 1,
  `slack_k8s_workload_list` TEXT NULL,
  `env_retention_period` INT NOT NULL DEFAULT 60,
  `eaas_tool_stack` TEXT NULL,
  `gpt_tool_stack` TEXT NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `smtp_config` TEXT NULL,
  `gpt_max_triggers` INT NOT NULL DEFAULT 2,
  `gpt_trigger_window` INT NOT NULL DEFAULT 60, -- in minutes
  `gpt_max_in_queue` INT NOT NULL DEFAULT 5,
  PRIMARY KEY (`thirdparty_app_id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_settings`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_settings` (
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `alias` VARCHAR(100) NOT NULL,
  `cloud_vendor` VARCHAR(100) NULL,
  `k8s_version` VARCHAR(100) NULL,
  `region` VARCHAR(100) NULL,
  `zone` VARCHAR(100) NULL,
  `instance_type` VARCHAR(100) NULL,
  `namespace` VARCHAR(100) NULL,
  `number_of_workers` INT NULL,
  `max_worker_nodes` INT NULL DEFAULT 2,
  `max_namespaces` INT NULL DEFAULT 2,
  `allow_auto_scale` SMALLINT NULL DEFAULT 1,
  `monthly_dollar_limit` INT NULL DEFAULT 0,
  `max_cluster_limit` INT NULL DEFAULT 3,
  `cluster_expires_in_hours` INT NULL,
  `jumphost_alias` VARCHAR(100) NULL,
  `ami` VARCHAR(100) NULL,
  `disk_size` VARCHAR(100) NULL,
  `ebs_volume` VARCHAR(100) NULL,
  `preemptible` SMALLINT NULL DEFAULT 0,
	`spot` SMALLINT NULL DEFAULT 0,
  `env_config` TEXT NULL,
  `access_key_id` TEXT NULL,
  `secret_access_key` TEXT NULL,
  `session_token` TEXT NULL,
  `subscription_id` VARCHAR(100) NULL,
  `azureUsername` VARCHAR(100) NULL,
  `tenantID` VARCHAR(100) NULL,
  `credentials_input_type` VARCHAR(100) NULL DEFAULT 'file',
  `on_signout` ENUM("none", "stop", "scaledown", "delete") NULL DEFAULT 'none',
  `after_signout_delay` INT NULL DEFAULT 30,
  `enable_wasm` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`thirdparty_app_id`, `alias`),
  CONSTRAINT `client_settings_ibfk_1`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_default_scripts`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_default_scripts` (
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `alias` VARCHAR(100) NOT NULL,
  `file_type` VARCHAR(100) NOT NULL,
  `order` INT NOT NULL,
  `file_name` VARCHAR(100) NULL,
  `file_content` TEXT NULL,
  PRIMARY KEY (`thirdparty_app_id`, `alias`, `file_type`, `order`),
  CONSTRAINT `client_default_scripts_ibfk_1`
    FOREIGN KEY (`thirdparty_app_id`, `alias`)
    REFERENCES `client_settings` (`thirdparty_app_id`, `alias`)
    ON UPDATE CASCADE
    ON DELETE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_jumphost`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_jumphost` (
  `id` VARCHAR(45) NOT NULL,
  `alias` VARCHAR(100) NOT NULL,
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `ip_addr` VARCHAR(20) NOT NULL,
  `pem_key` TEXT NOT NULL,
  `pem_key_filename` VARCHAR(100) NOT NULL,
  `added_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_modified_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `added_by` VARCHAR(100) NULL,
  `last_modified_by` VARCHAR(100) NULL,
  `server_username` VARCHAR(100) NULL,
  `is_docker_enabled` SMALLINT NULL DEFAULT 0,
  `roost_pem_key` TEXT NULL,
  `roost_local_key` VARCHAR(45) NULL,
  `health_check_time` TIMESTAMP NULL,
  `health_check_status` VARCHAR(255) NULL,
  `is_default` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `ip_addr_UNIQUE` (`ip_addr` ASC),
  INDEX `client_jumphost_tp_app_id_fk_idx` (`thirdparty_app_id` ASC),
  INDEX `client_jumphost_added_by_fk_idx` (`added_by` ASC),
  INDEX `client_jumphost_last_modified_by_fk_idx` (`last_modified_by` ASC),
  CONSTRAINT `client_jumphost_tp_app_id_fk`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT `client_jumphost_added_by_fk`
    FOREIGN KEY (`added_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `client_jumphost_last_modified_by_fk`
    FOREIGN KEY (`last_modified_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_ec2Launcher`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_ec2Launcher` (
  `id` VARCHAR(45) NOT NULL,
  `cluster_launcher_ip` VARCHAR(100) NOT NULL,
  `pem_key` TEXT NOT NULL,
  `pem_key_filename` VARCHAR(100) NOT NULL,
  `added_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_modified_on` TIMESTAMP NULL DEFAULT NULL,
  `server_username` VARCHAR(100) NOT NULL,
  `health_check_time` TIMESTAMP NULL,
  `health_check_status` VARCHAR(255) NULL,
  `auto_reset_ec2Launcher` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `cluster_launcher_ip_UNIQUE` (`cluster_launcher_ip` ASC)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `jumphost_cluster`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `jumphost_cluster` (
  `id` VARCHAR(100) NOT NULL,
  `jumphost_id` VARCHAR(100) NULL,
  `context_name` VARCHAR(200) NULL,
  `username` VARCHAR(200) NULL,
  `server_name` VARCHAR(200) NULL,
  `cluster_name` VARCHAR(200) NULL,
  `computed_cluster_name` VARCHAR(200) NULL,
  `region` VARCHAR(100) NULL,
  `kubeconfig_file_name` VARCHAR(100) NULL,
  `kubeconfig` TEXT NULL,
  `short_name` VARCHAR(100) NOT NULL,
  `added_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_modified_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `added_by` VARCHAR(100) NOT NULL,
  `last_modified_by` VARCHAR(100) NULL,
  PRIMARY KEY (`id`),
  INDEX `jumphost_cluster_jh_id_fk_idx` (`jumphost_id` ASC),
  INDEX `jumphost_cluster_added_by_fk_idx` (`added_by` ASC),
  INDEX `jumphost_cluster_last_modified_by_fk_idx` (`last_modified_by` ASC),
  CONSTRAINT `jumphost_cluster_jh_id_fk`
    FOREIGN KEY (`jumphost_id`)
    REFERENCES `client_jumphost` (`id`)
    ON UPDATE CASCADE
    ON DELETE SET NULL,
  CONSTRAINT `jumphost_cluster_added_by_fk`
    FOREIGN KEY (`added_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `jumphost_cluster_last_modified_by_fk`
    FOREIGN KEY (`last_modified_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `team_cluster_privileges`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `team_cluster_privilege` (
  `cluster_id` INT NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `node_username` VARCHAR(100) NULL,
  `ssh_key` TEXT NULL,
  `kubeconfig` TEXT NULL,
  PRIMARY KEY (`user_id`, `cluster_id`),
  INDEX `team_cluster_privilege_cluster_id_fk_idx` (`cluster_id` ASC),
  CONSTRAINT `team_cluster_privilege_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `team_cluster_privilege_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `preconfigured_client_admin`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `preconfigured_client_admin` (
  `email` VARCHAR(255) NOT NULL,
  `thirdparty_app_id` VARCHAR(32) NOT NULL,
  `requested_on` TIMESTAMP NULL,
  `signedup_on` TIMESTAMP NULL,
  `postlogin_user_id` VARCHAR(100) NULL,
  PRIMARY KEY (`email`, `thirdparty_app_id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `login_clients`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `login_clients` (
  `id` VARCHAR(45) NOT NULL,
  `client_name` VARCHAR(50) NOT NULL,
  `client_id` VARCHAR(255) NOT NULL,
  `client_secret` VARCHAR(255) NOT NULL,
  `additional_json` TEXT NULL,
  `secret_expiry` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active`  SMALLINT NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `zbio_login` -
-- To hold email id that are to be excluded from roost activity
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `zbio_login` (
  `email` VARCHAR(255) NOT NULL
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `sql_changes`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `sql_changes` (
  `id` VARCHAR(45) NOT NULL,
  `change_no` INT NOT NULL UNIQUE,
  `applied_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_schedule`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_schedule` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `jumphost_id` VARCHAR(45) NULL,
  `cluster_short_name` VARCHAR(100) NOT NULL,
  `cluster_alias` VARCHAR(100) NOT NULL,
  `wakeup_time` VARCHAR(10) NOT NULL,
  `sleep_time` VARCHAR(10) NOT NULL,
  `timezone` VARCHAR(100) NOT NULL,
  `days` TEXT NULL,
  `defer_in_hrs` INT NULL,
  `disable_power_down` SMALLINT NOT NULL DEFAULT 0,
  `status` VARCHAR(100) NULL,
  `status_updated_on` TIMESTAMP NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `last_modified_on` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  CONSTRAINT `user_schedule_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT `user_schedule_jh_id_fk_2`
    FOREIGN KEY (`jumphost_id`)
    REFERENCES `client_jumphost` (`id`)
    ON UPDATE CASCADE
    ON DELETE SET NULL
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `cron_user_schedule`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `cron_user_schedule` (
  `id` VARCHAR(45) NOT NULL,
  `jumphost_id` VARCHAR(45) NULL,
  `short_name` VARCHAR(100) NULL,
  `command` VARCHAR(20) NULL,
  `output` TEXT NULL,
  `error` TEXT NULL,
  `time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `cus_time_idx` (`time` DESC)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_cluster_namespace`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_cluster_namespace` (
  `user_id` VARCHAR(45) NOT NULL,
  `cluster_id` INT NOT NULL,
  `num_namespaces` INT NOT NULL DEFAULT 0,
  `ns_json` TEXT NULL,
  PRIMARY KEY (`user_id`, `cluster_id`),
  CONSTRAINT `ucn_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT `ucn_cluster_id_fk`
    FOREIGN KEY (`cluster_id`)
    REFERENCES `app_user_token` (`id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `user_schedule_audit`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `user_schedule_audit` (
  `id` VARCHAR(45) NOT NULL,
  `cluster_alias` VARCHAR(100) NOT NULL,
  `modified_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `user_id` VARCHAR(45) NOT NULL,
  `schedule_id` VARCHAR(45) NOT NULL,
  `action_type` ENUM("add", "delete", "defer", "update") NOT NULL,
  `old_values` TEXT NULL,
  `new_values` TEXT NULL,
  CONSTRAINT `user_schedule_audit_user_id_fk`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT `user_schedule_audit_schedule_id_fk`
    FOREIGN KEY (`schedule_id`)
    REFERENCES `user_schedule` (`id`)
    ON UPDATE CASCADE
    ON DELETE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_git_token`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_git_token` (
  `id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `app_name` VARCHAR(100) NOT NULL,
  `user_ip` VARCHAR(255) NULL,
  `username` VARCHAR(45) NULL,
  `access_token` VARCHAR(200) NOT NULL,
  `type` VARCHAR(100) NOT NULL DEFAULT "github",
  `cluster_config` TEXT NULL,
  `cluster_dependency` MEDIUMTEXT NULL,
  `cluster_limit` INT NOT NULL DEFAULT 0,
  `s3_region` VARCHAR(45) NULL,
  `s3_credentials` TEXT NULL,
  `ecr_credentials` TEXT NULL,
  `gcr_credentials` TEXT NULL,
  `docker_hub_credentials` TEXT NULL,
  `launch_darkly_config` TEXT NULL,
  `sns_config` TEXT NULL,
  `deployment_choice` VARCHAR(255) NULL,
  `deployment_namespace` VARCHAR(100) NULL,
  `env_create_delay` INT NOT NULL DEFAULT 120,
  `event_timeout` INT NOT NULL DEFAULT 1,
  `sleep_after` INT NOT NULL DEFAULT 2,
  `auto_expiry_hrs` INT NOT NULL DEFAULT 4,
  `event_choice` TEXT NULL,
  `chatgpt_token` VARCHAR(255) NULL,
  `slack_token` VARCHAR(255) NULL,
  `slack_channel_name` VARCHAR(45) NULL,
  `slack_channel_id` VARCHAR(255) NULL,
  `ms_teams_tenant_id` VARCHAR(45) NULL,
  `ms_teams_name` VARCHAR(255) NULL,
  `ms_teams_channel` VARCHAR(255) NULL,
  `service_fitness_json` TEXT NULL,
  `created_by` VARCHAR(45) NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `app_build_config` TEXT NULL,
  `app_build_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `app_deploy_config` TEXT NULL,
  `app_deploy_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `app_uninstall_config` TEXT NULL,
  `app_uninstall_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `app_test_config` TEXT NULL,
  `app_docker_compose_config` TEXT NULL,
  `app_image_list` TEXT NULL,
  `app_repo_name` VARCHAR(255) NULL,
  `app_repo_id` VARCHAR(45) NULL,
  `app_repo_branch` VARCHAR(255) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `app_env_config` TEXT NULL,
  `workflow_commit` SMALLINT NOT NULL DEFAULT 1,
  `webhook_error` TEXT NULL,
  `app_active` SMALLINT NOT NULL DEFAULT 1,
  `send_email` TEXT NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `cgt_tp_app_id_fk`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `client_workflow`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `client_workflow` (
  `id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `git_token_id` VARCHAR(45) NULL,
  `repo_id` VARCHAR(45) NULL,
  `repo_name` VARCHAR(200) NOT NULL,
  `branch_name` VARCHAR(255) NOT NULL,
  `trigger_events` TEXT NULL,
  `build_config` TEXT NULL,
  `build_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `deploy_config` TEXT NULL,
  `deploy_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `uninstall_config` TEXT NULL,
  `uninstall_config_type` VARCHAR(45) NOT NULL DEFAULT 'text',
  `test_config` TEXT NULL,
  `docker_compose_config` TEXT NULL,
  `image_list` TEXT NULL,
  `last_modified_on` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `last_modified_by` VARCHAR(45) NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `always_build_and_deploy` SMALLINT NOT NULL DEFAULT 0,
  `env_config` TEXT NULL,
  `wf_active` SMALLINT NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  CONSTRAINT `cwf_tp_app_id_fk`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE,
  CONSTRAINT `cwf_git_token_id_fk`
    FOREIGN KEY (`git_token_id`)
    REFERENCES `client_git_token` (`id`)
    ON DELETE SET NULL
    ON UPDATE CASCADE,
  CONSTRAINT `cwf_last_modified_by_fk`
    FOREIGN KEY (`last_modified_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
    ON DELETE SET NULL
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `git_events`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `git_events` (
  `id` VARCHAR(45) NOT NULL,
  `action` VARCHAR(45) NOT NULL,
  `number` INT NOT NULL,
  `title` TEXT NULL,
  `state` VARCHAR(45) NOT NULL,
  `date` TIMESTAMP NULL,
  `user_name` VARCHAR(45) NOT NULL,
  `user_img` VARCHAR(255) NULL,
  `release_tag_name` VARCHAR(45) NULL,
  `pr_merge_sha` VARCHAR(45) NULL,
  `head_ref` VARCHAR(255) NULL,
  `head_sha` VARCHAR(45) NULL,
  `base_ref` VARCHAR(255) NULL,
  `base_sha` VARCHAR(45) NULL,
  `source_repo_id` VARCHAR(45) NOT NULL,
  `source_repo_name` VARCHAR(45) NOT NULL,
  `source_owner_name` VARCHAR(45) NOT NULL,
  `target_repo_id` VARCHAR(45) NOT NULL,
  `target_repo_name` VARCHAR(45) NOT NULL,
  `target_owner_name` VARCHAR(45) NOT NULL,
  `full_json` MEDIUMTEXT NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `git_events_relation`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `git_events_relation` (
  `id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `event_id` VARCHAR(45) NOT NULL,
  `workflow_id` VARCHAR(45) NULL,
  `create_new_cluster` SMALLINT NOT NULL DEFAULT 0,
  `assigned_cluster_id` INT NULL,
  `assigned_namespace` VARCHAR(100) NULL,
  `current_status` VARCHAR(45) NULL,
  `status_details` TEXT NULL,
  `stop_status` SMALLINT NOT NULL DEFAULT 0,
  `status_updated_on` TIMESTAMP NULL,
  `application_end_points` TEXT NULL,
  `env_deleted` SMALLINT NOT NULL DEFAULT 0,
  `infra_output` TEXT NULL,
  `auto_expiry_hrs` INT NOT NULL DEFAULT 4,
  PRIMARY KEY (`id`),
  CONSTRAINT `ger_tp_app_id_fk`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE,
  CONSTRAINT `ger_event_id_fk`
    FOREIGN KEY (`event_id`)
    REFERENCES `git_events` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `ger_workflow_id_fk`
    FOREIGN KEY (`workflow_id`)
    REFERENCES `client_workflow` (`id`)
    ON UPDATE CASCADE
    ON DELETE SET NULL
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `cluster_actions`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `cluster_actions` (
  `id` VARCHAR(45) NOT NULL,
  `cluster_id` INT NOT NULL,
  `action_type` VARCHAR(45) NOT NULL,
  `action_on` TIMESTAMP NULL,
  `no_nodes` INT NOT NULL,
  `heterogenous` SMALLINT NOT NULL DEFAULT 0,
  `current_status` TEXT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `aws_instance_pricing`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `aws_instance_pricing` (
	`id` INT NOT NULL AUTO_INCREMENT,
	`region` VARCHAR(100) NOT NULL,
	`instanceFamily` VARCHAR(100) NOT NULL,
	`instanceType` VARCHAR(100) NOT NULL,
	`usageType` VARCHAR(100) NOT NULL,
	`description` VARCHAR(500) NOT NULL,
	`pricePerUnit` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `aws_storage_pricing`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `aws_storage_pricing` (
	`id` INT NOT NULL AUTO_INCREMENT,
	`region` VARCHAR(100) NOT NULL,
	`storageMedia` VARCHAR(100) NOT NULL,
	`volumeType` VARCHAR(100) NOT NULL,
	`usageType` VARCHAR(100) NOT NULL,
	`description` VARCHAR(500) NOT NULL,
	`pricePerUnit` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `gcp_instance_pricing`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `gcp_instance_pricing` (
  `idComputeCost` INT NOT NULL AUTO_INCREMENT,
  `Region` VARCHAR(100) NOT NULL,
  `ResourceGroup` VARCHAR(100) NOT NULL,
  `UsageType` VARCHAR(100) NOT NULL,
  `Cost` BIGINT NOT NULL DEFAULT 0,
  `Description` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`idComputeCost`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `gcp_storage_pricing`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `gcp_storage_pricing` (
  `idDiskCost` INT NOT NULL AUTO_INCREMENT,
  `Region` VARCHAR(100) NOT NULL,
  `ResourceGroup` VARCHAR(100) NOT NULL,
  `Cost` BIGINT NOT NULL DEFAULT 0,
  `Description` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`idDiskCost`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `gcp_instance_spec`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `gcp_instance_spec` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `MachineType` VARCHAR(100) NOT NULL,
  `vCPUs` VARCHAR(100) NOT NULL,
  `Memory` INT NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `notification`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `notification` (
  `id` VARCHAR(45) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `details` TEXT NULL,
  `date` TIMESTAMP NOT NULL,
  `roost_component` VARCHAR(255) NULL,
  `type` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `notification_user_rel`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `notification_user_rel` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `notif_id` VARCHAR(45) NOT NULL,
  `read_on` TIMESTAMP NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_notification_user_rel_notif_id`
    FOREIGN KEY (`notif_id`)
    REFERENCES `notification` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `fk_notification_user_rel_user_id`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `notification_thirdparty_rel`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `notification_thirdparty_rel` (
  `id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `notif_id` VARCHAR(45) NOT NULL,
  `read_by` VARCHAR(45) NULL,
  `read_on` TIMESTAMP NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_notification_thirdparty_rel_notif_id`
    FOREIGN KEY (`notif_id`)
    REFERENCES `notification` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `carbon_emission`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `carbon_emission` (
  `cloud_provider` VARCHAR(45) NOT NULL, -- AWS, GCP, AZURE
  `region` VARCHAR(45) NOT NULL,
  `moer_value` FLOAT NULL DEFAULT -1,
  `moer_updated_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`cloud_provider`, `region`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `app_specs`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `app_specs` (
  `id` VARCHAR(45) NOT NULL,
  `spec` VARCHAR(50) NOT NULL,
  `data` TEXT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `personal_access_token`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `personal_access_token` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(100) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NULL,
  `token_name` VARCHAR(100) NOT NULL,
  `access_token` VARCHAR(255) NOT NULL,
  `client_role` VARCHAR(100) NULL,
  `delete_eaas_app` SMALLINT NOT NULL DEFAULT 0,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `token_expiry` DATE NULL,
  `expired` SMALLINT NOT NULL DEFAULT 0,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_personal_access_token_user_id`
    FOREIGN KEY (`user_id`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `connector`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `connector` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NULL,
  `connector_name` VARCHAR(100) NOT NULL,
  `connector_type` VARCHAR(100) NOT NULL,
  `attributes` TEXT NOT NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `connector_scope` VARCHAR(45) NOT NULL DEFAULT "owner",
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `test_gpt`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `test_gpt` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NULL,
  `test_name` VARCHAR(100) NOT NULL,
  `git_info` TEXT NOT NULL,
  `ai_model_info` TEXT NOT NULL,
  `integration_info` TEXT NOT NULL,
  `additional_info` TEXT NOT NULL,
  `trigger_events` TEXT NULL,
  `created_on` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_on` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `test_timeout` INT NOT NULL DEFAULT 1,
  `webhook_error` TEXT NULL,
  `test_framework` TEXT NULL,
  `git_type` VARCHAR(45) NULL,
  `source_repo` VARCHAR(100) NULL,
  `source_branch` VARCHAR(200) NULL,
  `connector_ids` TEXT NULL,
  `git_ops` SMALLINT NOT NULL DEFAULT 1,
  `labels` TEXT NULL,
  `test_source` VARCHAR(100) NULL,
  `test_scope` VARCHAR(45) NOT NULL DEFAULT "owner",
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `test_gpt_events`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `test_gpt_events` (
  `id` VARCHAR(45) NOT NULL,
  `user_id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NULL,
  `git_event_id` VARCHAR(45) NULL,
  `status` TEXT NOT NULL,
  `time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `test_id` TEXT NOT NULL,
  `status_details` TEXT NOT NULL,
  `completion_time` TIMESTAMP NULL,
  `pr_create_duration` VARCHAR(45) NULL,
  `test_endpoints` TEXT NULL,
  `test_report` LONGTEXT NULL,
  `test_type` TEXT NULL,
  `test_result` TEXT NULL,
  `slack_timestamp` VARCHAR(255) NULL,
  `modification_time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `git_info` TEXT NULL,
  `ai_model_info` TEXT NULL,
  `additional_info` TEXT NULL,
  `integration_info` TEXT NULL,
  `retrigger_data` TEXT NULL,
  `labels` TEXT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `slack_troubleshoot`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `slack_troubleshoot` (
  `id` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL UNIQUE,
  `slack_channel_name` VARCHAR(45) NOT NULL,
  `slack_channel_id` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`id`),
CONSTRAINT `st_tp_app_id_fk`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `license_server`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `license_server` (
  `id` VARCHAR(45) NOT NULL,
  `display_name` VARCHAR(255) NULL,
  `thirdparty_app_id` VARCHAR(255) NULL,
  `license_key` VARCHAR(255) NOT NULL,
  `config` TEXT NULL,
  `roost_product_type` VARCHAR(45) NULL,
  `device_id` VARCHAR(45) NULL,
  `ip_address` VARCHAR(45) NULL,
  `enterprise_dns` VARCHAR(255) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_on` TIMESTAMP NULL,
  `is_trial` SMALLINT NOT NULL DEFAULT 0,
  `deleted` SMALLINT NOT NULL DEFAULT 0,
  `max_invocations` INT NOT NULL DEFAULT 60,
  `current_invocations` INT NOT NULL DEFAULT 0,
  `last_invoked_on` TIMESTAMP NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `license_audit`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `license_audit` (
  `id` VARCHAR(45) NOT NULL,
  `display_name` VARCHAR(255) NULL,
  `thirdparty_app_id` VARCHAR(255) NULL,
  `license_key` VARCHAR(255) NOT NULL,
  `device_id` VARCHAR(45) NULL,
  `ip_address` VARCHAR(45) NULL,
  `enterprise_dns` VARCHAR(255) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_accessed_on` TIMESTAMP NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `license_request`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `license_request` (
  `id` VARCHAR(45) NOT NULL,
  `full_name` VARCHAR(255) NULL,
  `company_email` VARCHAR(255) NOT NULL UNIQUE,
  `company_name` VARCHAR(255) NULL,
  `company_website` VARCHAR(255) NULL,
  `phone_number` VARCHAR(255) NULL,
  `linkedin_url` VARCHAR(255) NULL,
  `gpt_use` TEXT NULL,
  `email_domain` VARCHAR(255) NULL,
  `email_validated` SMALLINT NOT NULL DEFAULT 0,
  `email_otp` VARCHAR(10) NULL,
  `created_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_accessed_on` TIMESTAMP NULL,
  `otp_requested_on` TIMESTAMP NULL,
  `request_approved` SMALLINT NOT NULL DEFAULT 0,
  `license_id` VARCHAR(255) NULL,
  `user_id` VARCHAR(255) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `open_ai_model`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `open_ai_model` (
  `id` VARCHAR(45) NOT NULL,
  `open_ai_ip` VARCHAR(100) NULL,
  `model_name` VARCHAR(255) NOT NULL,
  `added_by` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `pem_key` TEXT NULL,
  `pem_key_filename` VARCHAR(100) NULL,
  `added_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `server_username` VARCHAR(100) NOT NULL,
  `state` VARCHAR(45) NOT NULL,
  `health_check_time` TIMESTAMP NULL,
  `health_check_status` VARCHAR(255) NULL,
  `zone` VARCHAR(100) NOT NULL,
  `vm_name` VARCHAR(100) NOT NULL,
  `gce_project` VARCHAR(100) NOT NULL,
  `firewall_rulename` VARCHAR(100) NULL,
  `machine_type` VARCHAR(100) NOT NULL,
  `boot_disk_size_gb` INT NOT NULL,
  `boot_disk_type` VARCHAR(100) NOT NULL,
  `image_family` VARCHAR(100) NOT NULL,
  `image_project` VARCHAR(100) NOT NULL,
  `gpu_type` VARCHAR(100) NULL,
  `gpu_count` INT NULL,
  `account_file_name` VARCHAR(100) NOT NULL,
  `account_file_content` TEXT NOT NULL,
  `script` TEXT NOT NULL,
  `deleted` SMALLINT NOT NULL DEFAULT 0,

  PRIMARY KEY (`id`),
  CONSTRAINT `fk_open_ai_model_added_by`
    FOREIGN KEY (`added_by`)
    REFERENCES `user` (`id`)
    ON UPDATE CASCADE,
  CONSTRAINT `fk_open_ai_model_tp_app_id`
    FOREIGN KEY (`thirdparty_app_id`)
    REFERENCES `client` (`thirdparty_app_id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `license_use_trail`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `license_use_trail` (
  `id` VARCHAR(45) NOT NULL,
  `app_user_id` VARCHAR(45) NULL,
  `thirdparty_app_id` VARCHAR(45) NULL,
  `display_name` VARCHAR(100) NULL,
  `license_key` VARCHAR(255) NOT NULL,
  `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `call_type` VARCHAR(100) NULL,
  `use_type` VARCHAR(100) NULL,
  `source_ip` VARCHAR(45) NULL,
  `app_username` VARCHAR(100) NULL,
  `user_id` VARCHAR(45) NULL,
  `device_id` VARCHAR(45) NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `ai_model_content_hash`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `ai_model_content_hash` (
  `id` VARCHAR(45) NOT NULL,
  `content_type` VARCHAR(45) NOT NULL,
  `content_text` TEXT NOT NULL,
  `content_hash` TEXT NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `ai_model_response`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `ai_model_response` (
  `id` VARCHAR(45) NOT NULL,
  `ai_model_type` VARCHAR(255) NOT NULL,
  `ai_model` VARCHAR(255) NOT NULL,
  "ai_temperature" FLOAT NOT NULL DEFAULT 0.6,
  `system_prompt_hash` TEXT NOT NULL,
  `user_prompt_hash` TEXT NOT NULL,
  `response` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `ai_model_response_audit`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `ai_model_response_audit` (
  `id` VARCHAR(45) NOT NULL,
  `response_id` VARCHAR(45) NOT NULL,
  `app_user_id` VARCHAR(45) NOT NULL,
  `used_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_ai_model_response_audit_response_id`
    FOREIGN KEY (`response_id`)
    REFERENCES `ai_model_response` (`id`)
    ON UPDATE CASCADE
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `label`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `label` (
  `id` VARCHAR(45) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
  `thirdparty_app_id` VARCHAR(45) NOT NULL,
  `description` VARCHAR(255) NULL,
  `colour` VARCHAR(10) NOT NULL,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- Table `invalid_access_token`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `invalid_access_token` (
  `id` VARCHAR(45) NOT NULL,
  `access_token` VARCHAR(255) NOT NULL,
  `expires_on` TIMESTAMP NOT NULL,
  `added_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
)
ENGINE = InnoDB
DEFAULT CHARACTER SET = 'utf8';

-- -----------------------------------------------------
-- View `license_verify`
-- -----------------------------------------------------
CREATE OR REPLACE VIEW license_verify_view AS
  SELECT  lut.use_type, u.username, u.email
  FROM license_use_trail AS lut
  LEFT JOIN user AS u ON lut.user_id = u.id
  WHERE u.is_active = 1;