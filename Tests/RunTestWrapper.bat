SET _result_dir="%1"
SHIFT

$*
SET ret_code=%ERRORLEVEL%
IF EXIST "%_result_dir%/result.txt" (
	FINDSTR /l "Skipped" "%_result_dir%/result.txt"
	IF NOT ERRORLEVEL 0 (
		SET ret_code=100
	)
)

EXIT %ret_code%
