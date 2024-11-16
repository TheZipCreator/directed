syn match directedType /[!-&*-/:-Z\\^-`|~][!-&*-Z\\^-z|~]*/
hi link directedType Type
syn match directedName /[a-z][!-&*-Z\\^-z|~]*/
hi link directedName Identifier
syn match directedArrow /->/
hi link directedArrow Operator
syn match directedAssign /:=/
hi link directedAssign Operator

syn match directedImport /import *".*" *as *[^ ]*/ contains=directedString,directedType
hi link directedImport Statement

syn match directedNumber /-\?[0-9]\+/
hi link directedNumber Number

" technically this is only for the `import` statement but whatever
syn region directedString start=/"/ skip=/\\/ end=/"/
hi link directedString String

syn match directedChar /'\(.\|\\.\)'/
hi link directedChar String


syn region directedComment start=/#/ end=/$/
hi link directedComment Comment

set ai
set ci
