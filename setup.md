# Working in this repository

## Create your team's copy

On the template repository, click **Use this template**, then **Create a new
repository**. Name it `serving-stack`, owned by one team member, with the rest
added as collaborators. Then clone it and add the course copy as `upstream`, so
you can pull a lab fix when one lands:

```bash
git clone https://github.com/<your-user>/serving-stack.git
cd serving-stack
git remote add upstream https://github.com/avis3nna/serving-stack.git
```

You push to `origin`, which is yours. You never push to `upstream`.

If a push fails with a 403, you are pushing over HTTPS to a repository you do
not own. Check the URL: `git remote -v`.

## One branch per teaching day

```bash
git checkout -b w2d2
# do the lab
git add app/main.py
git commit -m "w2d2: model behind /v1 on CPU"
git push -u origin w2d2
```

The reason for a branch a day is not ceremony. On the day a lab goes wrong, you
open yesterday's branch, which worked, and read what changed.

Merge the day's branch into `main` once its green check passes.

## Commit your measurements

Every lab that measures something writes a results file. Those are deliverables,
not scratch output, so they get committed. The `.gitignore` deliberately leaves
them alone.

## Two things never go in here

**Secrets.** From week 2 day 5 you have an API key in a `.env` file. A key
committed to a public repository has to be regenerated, and until it is, anyone
can read it.

**Models.** Weights are gigabytes, and git keeps every version of everything
forever. A repository with a model in its history is one nobody can clone again.

The `.gitignore` covers both. Leave it alone, and stage files by name rather
than reaching for `git add .`.
