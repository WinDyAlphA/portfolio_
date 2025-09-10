# Custom Rouge lexer for Solidity
# Drop-in skeleton so you can paste your rules.

require 'rouge'

module Rouge
  module Lexers
    # Replace the placeholder `root` state with your actual rules.
    # Reference: https://github.com/rouge-ruby/rouge#writing-a-new-lexer
    class Solidity < RegexLexer
      title 'Solidity'
      desc  'Ethereum smart contract language'
      tag   'solidity'
      aliases 'sol'
      filenames '*.sol'
      mimetypes 'text/x-solidity', 'application/x-solidity'

      # Minimal placeholder so the lexer loads without errors.
      state :root do
        rule %r/\s+/, Text::Whitespace
        rule %r/.+?/, Text
      end
    end
  end
end

# Usage examples in Markdown:
# ```solidity
# // your solidity code
# ```
# or
# ```sol
# // your solidity code
# ```

