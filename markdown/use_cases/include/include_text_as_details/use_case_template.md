### Include Text As Details

Use file inclusion to include text as details.

#### File to Be Included

Here's a file containing text to be included:

@[markdown](details.md)

#### Includer File

Here's a template file that includes it:

@[markdown](includer.md)

The treatment token ```:details``` specifies that the included text is to be treated as details.

@[:markdown](../interface.md)

#### File with Inclusion

Here's the finished file with the included details:

@[markdown](included.md)

And here are the included details, as rendered on this page.:

---

@[:markdown](included.md)
