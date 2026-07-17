# CCAudio


## ideas/todo
- Radio functionality, aka broadcasting, client always listens


## working with git

Never commit in main directly, main should always be executable and working!

### Create new branch for your feature:

```sh
git switch main
git pull
git switch -c feature/<branch-name>
```

### push branch to github

```sh
git push -u origin feature/<branch-name>
```

### when finished, merge in main

```sh
git checkout main
git pull
git merge feature/<branch-name>
```

### I want to update my branch with the latest main commits

```sh
git switch main
git pull
git switch feature/<branch-name>
git merge main
```
