Attribute VB_Name = "ImportAirfoil"
' ============================================================================
' ImportAirfoil.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Written without SolidWorks available;
'         expect to fix small API details on first run.
' ----------------------------------------------------------------------------
' What it does
'   Reads a normalized airfoil file (cad/airfoils/<name>.dat, two columns
'   x/c y/c, first line is a title) and inserts it into the active part as a
'   3D curve on the Front plane (XY), scaled to a chord you type in mm.
'   Afterwards: sketch on the Front plane, Convert Entities on the curve,
'   close it with a short line at the trailing edge, then Extrude (span) or
'   use it as a Loft profile.
'
' How to install
'   SolidWorks > Tools > Macro > New..., save as cad/macros/ImportAirfoil.swp,
'   then in the VBA editor: File > Import File... > this .bas file.
'   Delete the empty default module. Run with Tools > Macro > Run.
'
' Notes
'   * The API works in metres; the file is x/c, y/c; chord is asked in mm.
'   * The curve is created with InsertCurveFileBegin / InsertCurveFilePoint /
'     InsertCurveFileEnd, the same thing "Curve Through XYZ Points" does.
'   * Repeat for each element. Element angle of attack is set later by the
'     sketch that positions the element, driven by car_params.txt (fw_main_aoa_C etc.).
' ============================================================================
Option Explicit

Dim swApp As SldWorks.SldWorks
Dim swModel As SldWorks.ModelDoc2

Sub main()
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open a part first.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part.", vbExclamation
        Exit Sub
    End If

    ' --- pick the file ------------------------------------------------------
    Dim repoRoot As String
    repoRoot = RepoRootFromMacro()
    Dim fileName As String
    fileName = swApp.GetOpenFileName("Airfoil .dat file", repoRoot & "\cad\airfoils\", _
        "Airfoil (*.dat)|*.dat|All files (*.*)|*.*||", 0, "", "")
    If fileName = "" Then Exit Sub

    ' --- chord ---------------------------------------------------------------
    Dim chordStr As String
    chordStr = InputBox("Chord in mm", "Import airfoil", "400")
    If chordStr = "" Then Exit Sub
    Dim chord_m As Double
    chord_m = CDbl(chordStr) / 1000#

    ' --- read coordinates ------------------------------------------------------
    Dim xs() As Double, ys() As Double
    Dim n As Long
    n = ReadDat(fileName, xs, ys)
    If n < 3 Then
        MsgBox "Could not read at least 3 points from " & fileName, vbExclamation
        Exit Sub
    End If

    ' --- insert curve -------------------------------------------------------------
    Dim ok As Boolean
    ok = swModel.InsertCurveFileBegin()
    Dim i As Long
    For i = 0 To n - 1
        ' Front plane: X along chord, Y up, Z = 0 (metres)
        ok = swModel.InsertCurveFilePoint(xs(i) * chord_m, ys(i) * chord_m, 0#)
    Next i
    ok = swModel.InsertCurveFileEnd()
    If Not ok Then
        MsgBox "InsertCurveFileEnd failed. Check that the first and last points differ slightly " & _
               "(SolidWorks refuses two identical consecutive points).", vbExclamation
        Exit Sub
    End If

    ' Rename the new curve feature after the file
    Dim feat As SldWorks.Feature
    Dim featName As String
    featName = "(unnamed)"
    Set feat = swModel.FeatureManager.FeatureByPositionReverse(0)
    If Not feat Is Nothing Then
        feat.Name = "Airfoil_" & BaseName(fileName) & "_c" & chordStr
        featName = feat.Name
    End If
    swModel.ClearSelection2 True
    swModel.ViewZoomtofit2
    MsgBox "Inserted " & n & " points as curve '" & featName & "'." & vbCrLf & _
           "The curve lies in the model XY plane (z = 0), i.e. the default Front plane. " & _
           "Next: sketch on that plane, Convert Entities, close the trailing edge, Extrude.", vbInformation
End Sub

' Read a Selig-format .dat: title line, then "x y" pairs. Returns the count.
Private Function ReadDat(ByVal path As String, ByRef xs() As Double, ByRef ys() As Double) As Long
    Dim fnum As Integer: fnum = FreeFile
    Dim line As String, parts() As String
    Dim count As Long: count = 0
    ReDim xs(0 To 1023): ReDim ys(0 To 1023)
    Open path For Input As #fnum
    Dim first As Boolean: first = True
    Do While Not EOF(fnum)
        Line Input #fnum, line
        line = Trim$(line)
        If line = "" Then GoTo NextLine
        parts = SplitWhitespace(line)
        If first Then
            first = False
            ' title line: skip it unless it is already two numbers
            If UBound(parts) < 1 Then GoTo NextLine
            If Not (IsNumeric(parts(0)) And IsNumeric(parts(1))) Then GoTo NextLine
        End If
        If UBound(parts) >= 1 Then
            If IsNumeric(parts(0)) And IsNumeric(parts(1)) Then
                If count > UBound(xs) Then
                    ReDim Preserve xs(0 To UBound(xs) * 2): ReDim Preserve ys(0 To UBound(ys) * 2)
                End If
                xs(count) = CDbl(parts(0)): ys(count) = CDbl(parts(1))
                ' skip a point identical to the previous one
                If count > 0 Then
                    If Abs(xs(count) - xs(count - 1)) < 1E-09 And Abs(ys(count) - ys(count - 1)) < 1E-09 Then
                        GoTo NextLine
                    End If
                End If
                count = count + 1
            End If
        End If
NextLine:
    Loop
    Close #fnum
    If count = 0 Then
        ReadDat = 0
        Exit Function
    End If
    ' Open the trailing edge by a hair so the curve is not a closed loop with a
    ' coincident end point (the sketch later closes it with a line).
    If count >= 2 Then
        If Abs(xs(count - 1) - xs(0)) < 1E-09 And Abs(ys(count - 1) - ys(0)) < 1E-09 Then
            ys(count - 1) = ys(count - 1) - 0.0005
        End If
    End If
    ReDim Preserve xs(0 To count - 1): ReDim Preserve ys(0 To count - 1)
    ReadDat = count
End Function

Private Function SplitWhitespace(ByVal s As String) As String()
    Dim t As String
    t = Replace(s, vbTab, " ")
    t = Replace(t, ",", " ")
    Do While InStr(t, "  ") > 0
        t = Replace(t, "  ", " ")
    Loop
    SplitWhitespace = Split(Trim$(t), " ")
End Function

Private Function BaseName(ByVal path As String) As String
    Dim s As String
    s = Mid$(path, InStrRev(path, "\") + 1)
    If InStrRev(s, ".") > 0 Then s = Left$(s, InStrRev(s, ".") - 1)
    BaseName = s
End Function

' cad/macros/<this>.swp -> repo root is two levels up
Public Function RepoRootFromMacro() As String
    Dim p As String
    p = Application.SldWorks.GetCurrentMacroPathName
    If p = "" Then
        RepoRootFromMacro = CurDir$
    Else
        p = Left$(p, InStrRev(p, "\") - 1)          ' cad\macros
        p = Left$(p, InStrRev(p, "\") - 1)          ' cad
        p = Left$(p, InStrRev(p, "\") - 1)          ' repo root
        RepoRootFromMacro = p
    End If
End Function
