# github-backup

this is a script backing up all of your github repos in one place, put it in your server's cronjob

## requirements

```
sudo apt install git swipl curl
```

## setup

```bash
# create GitHub token at: https://github.com/settings/tokens
# required scope: repo

export GITHUB_USER="your-username"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
```

## usage

```bash
# sync to specific directory
./github-sync.pl /path/to/repos
```

## what it does

- clones new repositories
- pulls updates for existing repositories
- if pull fails (conflicts, diverged history), creates a timestamped backup clone, and clones the newest one
- handles both public and private repos
