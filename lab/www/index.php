<?php
// The victim "application". No sessions, no uploads, no unserialize, no
// includes, not a single vulnerable line.
//
// This is what the talk demonstrates: the flaw lives in the interpreter, not here.
echo 'ok';
