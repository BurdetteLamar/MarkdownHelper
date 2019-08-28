### Include with Added Comments

By default (that is, without option ```--pristine```) file inclusion adds comments that:

* Identify the includer file.
* Identify each includee file.

#### Includee File

```includee.md```:
```markdown
Text to be included.
```

#### Includer File

```includer.md```:
```markdown
@[:markdown](includee.md)
```

#### CLI

You can use the command-line interface to perform the inclusion.

##### Command

```sh
markdown_helper include includer.md included.md
```

#### API

You can use the API to perform the inclusion.

##### Ruby Code

```ruby
require 'markdown_helper'

markdown_helper = MarkdownHelper.new
markdown_helper.include(includer.md, included.md)
```

#### File with Inclusion and Added Comments

```included.md```:
```markdown
Text to be included.
```

The file path for the included file is relative to the .git directory.
