Attribute VB_Name = "ImportAirfoil"
' ============================================================================
' ImportAirfoil.bas  (SolidWorks VBA macro module)
' STATUS: untested, needs the app. Audited against the 2026 SP2.1 type
'         library after the first SolidWorks test of the other macros.
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
'   Delete the empty default module. Run with Tools > Macro > Run on the .swp
'   (not the .bas).
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention); it only sets the start folder of
'   the file dialog.
'
' Fixes after the 2026 test of the other macros
'   * FeatureManager.FeatureByPositionReverse does not exist (error 438);
'     the curve is found with ModelDocExtension.GetLastFeatureAdded.
'   * Line Input reads an LF-only file as one line; the .dat is now read
'     whole and split on vbLf with vbCr removed (LF and CRLF both work).
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
    ' InsertCurveFileBegin is a Sub on ModelDoc2 (returns nothing): call it as a
    ' statement. Assigning it (ok = ...) is the 2026 compile error
    ' "Expected Function or variable". Point and End return Boolean.
    Dim ok As Boolean, nBad As Long
    swModel.InsertCurveFileBegin
    Dim i As Long
    For i = 0 To n - 1
        ' Front plane: X along chord, Y up, Z = 0 (metres)
        If Not swModel.InsertCurveFilePoint(xs(i) * chord_m, ys(i) * chord_m, 0#) Then nBad = nBad + 1
    Next i
    If nBad > 0 Then Debug.Print nBad & " curve points were refused"
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
    Set feat = swModel.Extension.GetLastFeatureAdded
    If Not feat Is Nothing Then
        On Error Resume Next                ' name clash: keep the default name
        feat.Name = "Airfoil_" & BaseName(fileName) & "_c" & chordStr
        On Error GoTo 0
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
    Dim lines As Variant, li As Long
    Dim line As String, parts() As String
    Dim count As Long: count = 0
    ReDim xs(0 To 1023): ReDim ys(0 To 1023)
    lines = ReadTextLines(path)
    Dim first As Boolean: first = True
    For li = 0 To UBound(lines)
        line = Trim$(lines(li))
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
                xs(count) = Val(parts(0)): ys(count) = Val(parts(1))
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
    Next li
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

' Read a text file whole and split it into lines; works for LF and CRLF.
Private Function ReadTextLines(ByVal path As String) As Variant
    Dim fnum As Integer, txt As String, arr() As String, k As Long
    fnum = FreeFile
    Open path For Binary Access Read As #fnum
    If LOF(fnum) > 0 Then
        txt = Space$(LOF(fnum))
        Get #fnum, , txt
    End If
    Close #fnum
    arr = Split(txt, vbLf)
    For k = 0 To UBound(arr)
        arr(k) = Replace(arr(k), vbCr, "")
    Next k
    ReadTextLines = arr
End Function

' Walk up from the .swp folder until params\car_params.txt is found.
Public Function RepoRootFromMacro() As String
    Dim p As String
    p = Application.SldWorks.GetCurrentMacroPathName
    If p <> "" Then
        p = Left$(p, InStrRev(p, "\") - 1)
        Do While InStr(p, "\") > 0
            If Dir(p & "\params\car_params.txt") <> "" Then
                RepoRootFromMacro = p
                Exit Function
            End If
            p = Left$(p, InStrRev(p, "\") - 1)
        Loop
    End If
    RepoRootFromMacro = CurDir$
End Function
