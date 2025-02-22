# dex - Directory Exec

---

*dex* is a command line utility that allows you to define commands in a file in any directory, and then execute those commands.

For example, this repository has a file called **.dex.yaml**:

```yaml
- name: build
  desc: "Run through the build process."
  shell:
    - rm -f App-dex-*.tar.gz
    - perl Makefile.PL
    - make manifest
    - make dist
- name: clean
  desc: "Remove artifacts"
  shell:
    - rm -rf App-dex-*.tar.gz MANIFEST META.yml MYMETA.* Makefile blib
```

Running dex, without any argument, in this repository's root directory will give a menu:

```bash
$ dex
build       : Run through the build process.
clean       : Remove artifacts
```

At this point, running `dex build` would run the shell commands listed in the yaml file.  Commands can also be nested:

```yaml
- name: dev
  desc: "Control a local development server."
  children:
    - name: start
      desc: "Start a local development server on docker."
      shell:
        - docker-compose --project-directory ./ -f Docker/compose-osx-devel.yaml up
    - name: stop
      desc: "Stop a local development server on docker."
      shell:
        - docker-compose --project-directory ./ -f Docker/compose-osx-devel.yaml down
    - name: reset
      desc: "Delete the database volume."
      shell:
        - docker-compose --project-directory ./ -f Docker/compose-osx-devel.yaml down -v
- name: test
  desc: "Run the tests."
  shell:
    - docker-compose --project-name testing --project-directory ./ -f Docker/compose-osx-test.yaml up
    - docker-compose --project-name testing --project-directory ./ -f Docker/compose-osx-test.yaml down
```

The children define further arguments that could be used, such as `dex dev start`, and the menu indents to show child commands:

```bash
$ dex
dev         : Control a local development server.
    start       : Start a local development server on docker.
    stop        : Stop a local development server on docker.
    reset       : Delete the database volume.
test        : Run the tests.
```

## Config File Version 2

*dex* now has a new configuration format. The existing format is still supported and will function the same, but using this new format adds some new options and features that allow you to run more dynamic commands. 

```YAML
     version: 2
     vars:
       root_var: 'I can be used in every block'
       some_list:
         - 'this'
         - 'that'  
       work_dir: 
         from_command: pwd | tr -d '\n'  

     blocks:
       - name: var-example 
         desc: An Example block command with global and block variables.
         vars:
           some_string: 'for this block only' 
           env_var:
             from_env: SECOND_CMD 
             default: 0
         commands:
           - exec: echo 'Global var work_dir: [% work_dir %], block variable [% some_string %] '
           - exec: echo 'SECOND_CMD is set'
             condition: [%env_var%] -eq 1
       - name: loop-example
         desc: An Example block command that looks over a list var.
         commands: 
           - exec: echo 'repeating command with variable [% var %]
             for-vars: some_list  
```

The root `vars` attribute defines variables that can be used in any block by enclosing the name of the variable
within `[%` and `%]`.  These variables can be a string, number a list containing a combination of either. 

```YAML
     vars:
       string_var: 'I can be used in every block'
       number:var: 23423
       list_var:
         - 'foo'
         - 'bar'
         - 34
```

You can also configure variables to be initialized from the output of an external command or by referencing an environment variable.

```YAML
     vars:
       perl5_version: 
         from_command: "perl -MConfig -e 'print $Config{version}'"
         default: 'command failed'
       perl5_lib: 
         from_env: PERL5LIB
         default: 'NO PERL5LIB SET'

``` 

The `from_command` attribute will execute the set command and, assuming the command exits with a value of 0, assign its' STDOUT to the value of the variable. If the command returns multiple lines the variable will become a list containing
each line.  If the command exits with a non-zero value then the variable will be assigned the `default` attribute value
or remain undefined if no 'default' attribute is provided.

`from_env` will check for a matching environment variable and if found will assign that value to the variable. When the environment variable is not defined the 'default' attribute value is used.

`blocks` is similar to the root list in the Standard Format. It defines a list of named blocks of commands and nestable sub blocks of commands to run.  

```YAML
      blocks:
       - name: block-example
         desc: An Example block.
         vars:
           local_var: 'for this block only' 
         commands:
           - diag: '[%local_var%] execute update'
           - exec:  /bin/uptime
```

Within each block you can define `vars` with the same options the root `vars` attribute, but these variables will only be available for commands in that block.  

The `commands` attribute replaces the `shell` attribute and lets you define three kinds of commands.

  * `diag` - This command is an alias for echo and will print the string template to the terminal.

  * `dir`  - Sets the working directory for commands executed after this.  

  * `exec` - A command to execute.

The following configuration attributes are also available for each command.

  * `condition` - Takes a condition in the same format as the *test* command. If the condition returns false the command
    will be skipped.

  * `for-vars` - Can be a list or the name of variable that contains a list.  The command will be executed for each element of the list.  The value and index for each element in the list will be available as the `var` and `index` variables.

```YAML
      blocks:
       - name: for-vars-example
         desc: An Example block.
         vars:
           local_list: 
             - 1
             - 2
             - 3
         commands:
           - diag: 'value [%var%] at index [%index%]'
             for-vars: local_list
```     
