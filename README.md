# ab-devcontainer project

### Add to new project

```git submodule add -b dev https://github.com/agilebeat-inc/ab-devcontainer.git .devcontainer```

It is a template for devcontainer configuration

### GitHub configuration

BLUF: Devcontainer plugin for vsc will use credentails cached by github client on host server automatically. Just [download](https://github.com/cli/cli/releases/tag/v2.60.1) and install proper for your operating system version of github client. At the time of writing the version is v2.60.1.


#### [Sharing Git credentials with your devcontainer.](https://code.visualstudio.com/remote/advancedcontainers/)

The Dev Containers extension provides out of the box support for using local Git credentials from inside a container. In this section, we'll walk through the two supported options.

If you do not have your user name or email address set up locally, you may be prompted to do so. You can do this on your local machine by running the following commands:

```
git config --global user.name "Your Name"
git config --global user.email "your.email@address"
```
The extension will automatically copy your local .gitconfig file into the container on startup so you should not need to do this in the container itself.

Using a credential helper

If you use HTTPS to clone your repositories and have a credential helper configured in your local OS, no further setup is required. Credentials you've entered locally will be reused in the container and vice versa.

[see more ...](https://code.visualstudio.com/remote/advancedcontainers/)

#### [Caching credentials on host so that devcontainer can use it.](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git)

GitHub CLI will automatically store your Git credentials for you when you choose HTTPS as your preferred protocol for Git operations and answer "yes" to the prompt asking if you would like to authenticate to Git with your GitHub credentials.

- [Install](https://github.com/cli/cli#installation) GitHub CLI on macOS, Windows, or Linux.
- In the command line, enter gh auth login, then follow the prompts.
- When prompted for your preferred protocol for Git operations, select HTTPS.
- When asked if you would like to authenticate to Git with your GitHub credentials, enter Y.

For more information about authenticating with GitHub CLI, see [gh auth login](https://cli.github.com/manual/gh_auth_login).

[see more ...](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git)

#### Change `zsh` to `bash` on mac


Copilot
Switching your Mac's default shell to Bash is quite straightforward. Here are the steps:

1. Open Terminal: You can find it in Applications > Utilities > Terminal.
2. Check Current Shell: Type echo $SHELL to see which shell you're currently using.
3. Change to Bash: Type chsh -s /bin/bash and press Enter. You might be prompted to enter your password.
4. Restart Terminal: Close and reopen Terminal to see the changes.

