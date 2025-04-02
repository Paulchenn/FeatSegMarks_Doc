@echo off
setlocal enabledelayedexpansion

:: Definiere den Quellpfad und den Zielordner
set "source=C:\Users\GLP1RNG\Documents\2024_BA_Bosch\thesis.pdf"
set "destination=C:\Users\GLP1RNG\Documents\2024_BA_Bosch\"

:: Hole das aktuelle Datum und die Uhrzeit im Format yyyyMMdd_hhmm
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "date=!datetime:~0,8!"
set "time=!datetime:~8,4!"
set "formatted_time=!date!_!time!__Bachelorarbeit__V1.pdf"

:: Erstelle den vollständigen Pfad für die neue Datei
set "target=!destination!!formatted_time!"

:: Kopiere die Datei
copy "%source%" "!target!"

:: Ausgabe
echo Datei wurde erfolgreich kopiert nach: !target!
endlocal