/*

 Backup strategy for multiple resource types, including RDS and DynamoDB,
 usign AWS Backup.

 See: README.md for a summary on how this works and how to customize it

*/
resource "aws_backup_vault" "backup_vault" {
  name = "backup_vault"
}

/*

 Add extra security to the AWS backup vault by applying a resource policy
 that prevents anyone from:
 
    * Removing the recovery points
    * Deleting the backup vault
    * Change or delete the resource policy for the vault (which imposes the
      previous restrictions)

 This means that only the root account will ever be able to remove this
 backup vault! [0]

 Terraform doesn't have support for creating a backup vault access policy
 so we need to use local-exec and run the `aws cli` to create it.

 [0] https://docs.amazonaws.cn/en_us/general/latest/gr/root-vs-iam.html

*/

resource "local_file" "vault_access_policy" {
  filename = "vault-access-policy.json"
  file_permission = 0644
  content  = <<EOT
    {
      "Version": "2012-10-17",
      "Statement": [
          {
            "Effect": "Deny",
            "Principal": "*",
            "Action": ["backup:DeleteRecoveryPoint",
                       "backup:DeleteBackupVault",
                       "backup:PutBackupVaultAccessPolicy",
                       "backup:DeleteBackupVaultAccessPolicy"],
            "Resource": "${aws_backup_vault.backup_vault.arn}"
          }
      ]
    }
    EOT
}

resource "null_resource" "put-backup-vault-access-policy" {
  triggers = {
    policy = local_file.vault_access_policy.content
  }

  provisioner "local-exec" {
    command = "aws backup put-backup-vault-access-policy --region ${data.aws_region.current.name} --backup-vault-name ${aws_backup_vault.backup_vault.name} --policy file://vault-access-policy.json"
  }
  depends_on = ["aws_backup_vault.backup_vault",
  "local_file.vault_access_policy"]
}

/*
 Define the backup plans:

    * How often are backups created?
    
    * For how many days are we storing the backups?

 Also define tags for selecting which resources are applied to each
 backup plan.
*/
resource "aws_backup_plan" "daily_two_weeks" {
  name = "daily_two_weeks"
  rule {
    rule_name = "daily_two_weeks"
    target_vault_name = aws_backup_vault.backup_vault.name

    # every day at 3am
    schedule = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = "14"
    }
  }
}

resource "aws_backup_selection" "daily_two_weeks_selection" {
  plan_id = aws_backup_plan.daily_two_weeks.id
  name = "daily_two_weeks_selection"
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSBackupDefaultServiceRole"

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "daily_two_weeks"
  }
}

resource "aws_backup_plan" "three_times_a_day_two_weeks" {
  name = "three_times_a_day_two_weeks"
  rule {
    rule_name = "three_times_a_day_two_weeks"
    target_vault_name = aws_backup_vault.backup_vault.name

    # every day at 0:00, 8:00 and 16:00
    schedule = "cron(0 0/8 * * ? *)"

    lifecycle {
      delete_after = "14"
    }
  }
}

resource "aws_backup_selection" "three_times_a_day_two_weeks_selection" {
  plan_id = aws_backup_plan.three_times_a_day_two_weeks.id
  name = "three_times_a_day_two_weeks_selection"
  iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSBackupDefaultServiceRole"

  selection_tag {
    type = "STRINGEQUALS"
    key = "backup_policy"
    value = "three_times_a_day_two_weeks"
  }
}
