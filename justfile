set shell := ['bash', '-uc']
set windows-shell := ['cmd', '/c']

name := 'twodee'
out_dir := 'bin'
src_dir := 'src'

# These shouldn't need to be changed
ext := if os_family() == 'windows' { '.exe' } else { '' }
odin_exe := 'odin'
debug_suffix := '_debug'
odin_args := '-vet -vet-cast -vet-tabs -strict-style'
build_args := odin_args + ' -keep-executable'
debug_args := build_args + ' -debug'
release_args := build_args + ' -o:speed -subsystem:windows'

# Default recipe which runs `build-release`
default: build-release

_init:
	@just _init-{{os_family()}}

_init-windows:
	@-mkdir {{out_dir}} >nul 2>nul

_init-unix:
	@-mkdir -p {{out_dir}} >/dev/null 2>&1

# Cleans the build directory
clean:
	@just _clean-{{os_family()}}

_clean-windows:
	-rmdir /S /Q {{out_dir}} >nul 2>nul

_clean-unix:
	-rm -f {{out_dir}} >/dev/null 2>&1

# Compiles with debug profile
build-debug *args: _init
	{{odin_exe}} build {{src_dir}} -out:{{out_dir}}/{{name}}{{debug_suffix}}{{ext}} {{debug_args}} {{args}}

# Compiles with release profile
build-release *args: _init
	{{odin_exe}} build {{src_dir}} -out:{{out_dir}}/{{name}}{{ext}} {{release_args}} {{args}}
alias build := build-release

# Runs `odin check`
check *args:
	{{odin_exe}} check {{src_dir}} {{odin_args}} {{args}}

# Runs the application with debug profile
run-debug *args: _init
	{{odin_exe}} run {{src_dir}} -out:{{out_dir}}/{{name}}{{debug_suffix}}{{ext}} {{debug_args}} {{args}}
alias debug := run-debug

# Runs the application with release profile
run-release *args: _init
	{{odin_exe}} run {{src_dir}} -out:{{out_dir}}/{{name}}{{ext}} {{release_args}} {{args}}
alias run := run-release
