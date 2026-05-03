# Shared stamp hashing logic used by script/tdd_verify (write side) and
# script/checks/verify_tests (read side). One implementation so the hashes
# always agree.
#
# Hashing rules:
#   - `sha8(s)` — first 8 hex chars of SHA-256 of the string.
#   - per-test hash — hash of the test function body (inclusive of `func`
#     declaration line through the line immediately before the next
#     top-level delimiter), with `# AI-DEV:` lines removed and trailing
#     whitespace stripped per line.
#   - setup hash — concatenation of all non-test units (other funcs + `var`
#     top-level declarations), same per-line processing, then hashed.
#
# The "drop line immediately before next delimiter" rule matches the
# long-standing bash `get_function_body` convention: typical test files have
# a blank line between functions, and the blank line counts as separator,
# not as part of the prior function.

require 'digest'

module TestStamp # rubocop:disable Style/Documentation
  module_function

  def sha8(str)
    Digest::SHA256.hexdigest(str)[0, 8]
  end

  # Parse a GDScript test file into units. Returns Array of Hashes:
  #   {kind: :func|:top, name: String, body: String}
  # Body includes the declaration line through the line immediately before
  # the next top-level delimiter (func/class/var/const/signal/enum/# ──).
  def parse_units(path)
    lines = File.readlines(path)
    delim_re = /^(?:func |class |var |const |signal |enum |# ──)/
    units = []
    i = 0
    while i < lines.size
      line = lines[i]
      if line =~ /^func\s+(\w+)\s*\(/
        name = Regexp.last_match(1)
        j = i + 1
        j += 1 while j < lines.size && lines[j] !~ delim_re
        # Bash drops the line immediately before a delimiter (typical blank
        # separator), but when there's no next delimiter (last func in file)
        # bash keeps everything through EOF.
        end_idx = j >= lines.size ? lines.size - 1 : [i, j - 2].max
        body = lines[i..end_idx].join
        units << { kind: :func, name: name, body: body }
        i = j
      elsif line.start_with?('var ')
        units << { kind: :top, name: line.strip, body: line }
        i += 1
      else
        i += 1
      end
    end
    units
  end

  def _process(body)
    # Bash equivalent: `grep -v '# AI-DEV:' | sed 's/[[:space:]]*$//'` feeding
    # into `body=$(...)`. Command substitution strips ALL trailing newlines,
    # so the processed body never ends with `\n` — mimic that with `sub`.
    body.each_line.reject { |l| l.include?('# AI-DEV:') }
        .map(&:rstrip)
        .join("\n")
        .sub(/\n+\z/, '')
  end

  def stamp_body_for(units, name)
    unit = units.find { |u| u[:kind] == :func && u[:name] == name }
    return '' unless unit

    _process(unit[:body])
  end

  # Setup body = all top-level `var` lines joined with newlines, concatenated
  # with all non-test function bodies (no separator between them). Matches
  # the historical bash `get_setup_body`:
  #   setup_body=$(grep '^var ' | sed trailing)       # newline-joined block
  #   setup_body="${setup_body}${func_body}"           # append each func body
  def setup_body(units, test_names)
    var_block = units.select { |u| u[:kind] == :top }
                     .map { |u| u[:body].rstrip }
                     .join("\n")
    func_parts = units.select { |u| u[:kind] == :func && !test_names.include?(u[:name]) }
                      .map { |u| _process(u[:body]) }
                      .join
    var_block + func_parts
  end

  def hash_test(units, test_name)
    sha8(stamp_body_for(units, test_name))
  end

  def hash_setup(units, test_names)
    sha8(setup_body(units, test_names))
  end
end
