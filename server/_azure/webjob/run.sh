#!/bin/bash
# Scheduled WebJob: finishes interrupted checks, re-sends failed emails and
# deletes old documents (the cPanel cron job's job).
php /home/site/wwwroot/bys/retry.php
