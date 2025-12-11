#!/usr/bin/env swipl
:- initialization(main, main).
:- use_module(library(http/json)).

% configuration
github_user(User) :-
    getenv('GITHUB_USER', User), !.
github_user(_) :-
    writeln('error: GITHUB_USER environment variable not set'),
    halt(1).

github_token(Token) :-
    getenv('GITHUB_TOKEN', Token), !.
github_token(_) :-
    writeln('error: GITHUB_TOKEN environment variable not set'),
    writeln('create a token at: https://github.com/settings/tokens'),
    halt(1).

main(Argv) :-
    (Argv = [TargetDir|_] ->
        true
    ;
        format('target directory not given', []),
        halt(1)
    ),
    github_user(User),
    format('fetching repositories for user: ~w~n', [User]),
    format('target directory: ~w~n', [TargetDir]),
    ensure_directory(TargetDir),
    get_all_repositories(User, Repos),
    length(Repos, RepoCount),
    format('found ~w repositories~n', [RepoCount]),
    sync_repositories(Repos, TargetDir),
    halt(0).

% ensure target directory exists
ensure_directory(Dir) :-
    format(atom(Cmd), 'mkdir -p ~w', [Dir]),
    shell(Cmd).

% get all repositories with pagination support
get_all_repositories(User, AllRepos) :-
    get_repositories_page(User, 1, [], AllRepos).

get_repositories_page(User, Page, Acc, AllRepos) :-
    github_token(Token),
    format(atom(Url), 'https://api.github.com/user/repos?per_page=100&page=~w&affiliation=owner', [Page]),
    format(atom(Cmd), 'curl -s -H "Authorization: token ~w" "~w"', [Token, Url]),
    setup_call_cleanup(
        open(pipe(Cmd), read, Stream),
        read_string(Stream, _, Json),
        close(Stream)
    ),
    atom_string(JsonAtom, Json),
    atom_json_dict(JsonAtom, RepoList, []),
    (is_list(RepoList), RepoList \= [] ->
        extract_repo_info(RepoList, Repos),
        append(Acc, Repos, NewAcc),
        length(NewAcc, Count),
        NextPage is Page + 1,
        format('retrieved page ~w (~w repos so far)~n', [Page, Count]),
        get_repositories_page(User, NextPage, NewAcc, AllRepos)
    ;
        AllRepos = Acc
    ).

% extract repository names and clone URLs from JSON
extract_repo_info([], []).
extract_repo_info([Repo|Rest], [repo(Name, CloneUrl)|Repos]) :-
    is_dict(Repo),
    get_dict(name, Repo, Name),
    get_dict(clone_url, Repo, CloneUrl),
    !,
    extract_repo_info(Rest, Repos).
extract_repo_info([_|Rest], Repos) :-
    extract_repo_info(Rest, Repos).

% sync all repositories
sync_repositories([], _).
sync_repositories([repo(Name, CloneUrl)|Rest], TargetDir) :-
    format('processing: ~w~n', [Name]),
    format(atom(RepoPath), '~w/~w', [TargetDir, Name]),
    (exists_directory(RepoPath) ->
        pull_repository(RepoPath, Name)
    ;
        clone_repository(CloneUrl, TargetDir, Name)
    ),
    sync_repositories(Rest, TargetDir).

% clone a new repository
clone_repository(CloneUrl, TargetDir, Name) :-
    format('cloning ~w...~n', [Name]),
    % replace https://github.com with https://TOKEN@github.com for private repos
    github_token(Token),
    atom_string(CloneUrl, CloneUrlStr),
    replace_url_with_token(CloneUrlStr, Token, AuthUrl),
    format(atom(Cmd), 'git clone ~w ~w/~w 2>&1', [AuthUrl, TargetDir, Name]),
    shell(Cmd, Status),
    (Status = 0 ->
        format('successfully cloned ~w~n', [Name])
    ;
        format('failed to clone ~w (status: ~w)~n', [Name, Status])
    ).

% pull updates for existing repository
pull_repository(RepoPath, Name, CloneUrl, TargetDir) :-
    format('pulling updates for ~w...~n', [Name]),
    format(atom(Cmd), 'cd ~w && git pull 2>&1', [RepoPath]),
    shell(Cmd, Status),
    (Status = 0 ->
        format('successfully updated ~w~n', [Name])
    ;
        % pull failed - clone to backup location
        format('pull failed for ~w, creating backup clone...~n', [Name]),
        get_time(Time),
        format_time(atom(Timestamp), '%Y%m%d_%H%M%S', Time),
        format(atom(BackupPath), '~w_conflict_~w', [RepoPath, Timestamp]),
        format('cloning fresh copy to: ~w~n', [BackupPath]),
        github_token(Token),
        atom_string(CloneUrl, CloneUrlStr),
        replace_url_with_token(CloneUrlStr, Token, AuthUrl),
        format(atom(CloneCmd), 'git clone ~w ~w 2>&1', [AuthUrl, BackupPath]),
        shell(CloneCmd, CloneStatus),
        (CloneStatus = 0 ->
            format('successfully created backup clone~n')
        ;
            format('failed to create backup clone (status: ~w)~n', [CloneStatus])
        )
    ).

% replace github.com URL with authenticated URL
replace_url_with_token(Url, Token, AuthUrl) :-
    sub_string(Url, _, _, _, "https://github.com"),
    !,
    atomics_to_string(['https://', Token, '@github.com'], '', Prefix),
    split_string(Url, "/", "", ["https:", "", "github.com"|Rest]),
    atomics_to_string([Prefix|Rest], "/", AuthUrl).
replace_url_with_token(Url, _, Url).  % fallback if URL format unexpected, this wont work on private repos tho