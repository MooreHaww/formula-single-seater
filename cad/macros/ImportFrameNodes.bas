Attribute VB_Name = "ImportFrameNodes"
' ============================================================================
' ImportFrameNodes.bas  (SolidWorks VBA macro module)
' STATUS: first version ran in SolidWorks 2026 SP2.1 Student (116 lines, once
'         the CSVs had CRLF endings); this per-group version is untested,
'         needs the app.
' ----------------------------------------------------------------------------
' What it does
'   Reads cad/frame/frame_nodes.csv (node,x_mm,y_mm,z_mm,note) and
'   cad/frame/frame_tubes.csv (tube,node_a,node_b,group,od_mm,wall_mm,...)
'   and draws one 3D-sketch line per tube between the node coordinates.
'   One 3D sketch per tube group, so each group is one box select later:
'     FRAME_hoop, FRAME_hoop_brace, FRAME_sis, FRAME_bulkhead,
'     FRAME_sidepod, FRAME_front, FRAME_rear
'   (a group not in that list gets its own FRAME_<group> sketch at the end).
'   Within a sketch, lines that share a node share the end point (AddToDB is
'   off so inference merges them; this worked in the 2026 test).
'   Afterwards, per group (docs/cad_playbook/02_chassis.md steps 2 to 6):
'     hide the other sketches, box select all lines, Insert > Weldments >
'     Structural Member, rename the feature SM_<group>.
'   The lines carry no equations: regenerate the CSVs from MATLAB
'   (frame_layout.m) and rerun this macro when the hardpoints change. Delete
'   or rename the old FRAME_* sketches first; the macro stops if one exists.
'
' Repo root
'   Found by walking up from the folder of the running .swp until a folder
'   with params\car_params.txt is found. Save the .swp anywhere inside the
'   repo (cad\macros is the convention).
'
' How to install and run: see cad/macros/README.md (Tools > Macro > New,
'   File > Import File, then Tools > Macro > Run on the .swp, not the .bas).
'
' Fixes after the 2026 test
'   * FeatureManager.FeatureByPositionReverse does not exist (error 438).
'     The sketch is now named through the sketch object itself
'     (SketchManager.ActiveSketch, cast to Feature, before exiting).
'   * Line Input read an LF-only CSV as one line. Files are now read whole and
'     split on vbLf with vbCr removed, so LF and CRLF both work.
' ============================================================================
Option Explicit

Sub main()
    Dim swApp As SldWorks.SldWorks
    Dim swModel As SldWorks.ModelDoc2
    Set swApp = Application.SldWorks
    Set swModel = swApp.ActiveDoc
    If swModel Is Nothing Then
        MsgBox "Open the part that should receive the frame skeleton.", vbExclamation
        Exit Sub
    End If
    If swModel.GetType <> swDocPART Then
        MsgBox "The active document must be a part.", vbExclamation
        Exit Sub
    End If

    Dim repoRoot As String
    repoRoot = RepoRootFromMacroPath()
    Dim nodesFile As String, tubesFile As String
    nodesFile = repoRoot & "\cad\frame\frame_nodes.csv"
    tubesFile = repoRoot & "\cad\frame\frame_tubes.csv"
    If Dir(nodesFile) = "" Or Dir(tubesFile) = "" Then
        MsgBox "Run matlab/cad/frame_layout.m first; expected " & nodesFile & " and " & tubesFile, vbExclamation
        Exit Sub
    End If

    ' --- nodes: name -> (x, y, z) in metres -------------------------------------
    Dim nodes As Object
    Set nodes = CreateObject("Scripting.Dictionary")
    Dim lines As Variant, k As Long, ln As String, parts() As String
    lines = ReadTextLines(nodesFile)
    For k = 1 To UBound(lines)                              ' line 0 is the header
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 3 Then
                nodes(Trim$(parts(0))) = Array(Val(parts(1)) / 1000#, Val(parts(2)) / 1000#, Val(parts(3)) / 1000#)
            End If
        End If
    Next k

    ' --- tubes grouped: group -> Collection of Array(nodeA, nodeB) --------------
    Dim groups As Object
    Set groups = CreateObject("Scripting.Dictionary")
    Dim missing As Long, g As String
    lines = ReadTextLines(tubesFile)
    For k = 1 To UBound(lines)
        ln = Trim$(lines(k))
        If ln <> "" And Left$(ln, 1) <> "#" Then
            parts = Split(ln, ",")
            If UBound(parts) >= 3 Then
                If nodes.Exists(Trim$(parts(1))) And nodes.Exists(Trim$(parts(2))) Then
                    g = Trim$(parts(3))
                    If g = "" Then g = "other"
                    If Not groups.Exists(g) Then groups.Add g, New Collection
                    groups(g).Add Array(Trim$(parts(1)), Trim$(parts(2)))
                Else
                    missing = missing + 1
                End If
            End If
        End If
    Next k
    If groups.Count = 0 Then
        MsgBox "No tubes read from " & tubesFile, vbExclamation
        Exit Sub
    End If

    ' --- order: the seven known groups first, then anything else ---------------
    Dim order As Collection
    Set order = New Collection
    Dim known As Variant, key As Variant
    known = Array("hoop", "hoop_brace", "sis", "bulkhead", "sidepod", "front", "rear")
    For k = 0 To UBound(known)
        If groups.Exists(known(k)) Then order.Add known(k)
    Next k
    For Each key In groups.Keys
        If Not InArray(CStr(key), known) Then order.Add CStr(key)
    Next key

    ' refuse to run twice into the same part
    For Each key In order
        If FeatureExists(swModel, "FRAME_" & key) Then
            MsgBox "A feature named FRAME_" & key & " already exists. Delete or rename the old FRAME_* sketches, then rerun.", vbExclamation
            Exit Sub
        End If
    Next key

    ' --- one 3D sketch per group --------------------------------------------------
    Dim skMgr As SldWorks.SketchManager
    Set skMgr = swModel.SketchManager
    skMgr.AddToDB = False          ' inference on, so shared nodes merge into one point
    skMgr.DisplayWhenAdded = False

    Dim report As String, total As Long, n As Long, item As Variant
    Dim pa As Variant, pb As Variant
    Dim swSketch As SldWorks.Sketch, swFeat As SldWorks.Feature, wanted As String
    For Each key In order
        wanted = "FRAME_" & key
        swModel.ClearSelection2 True
        skMgr.Insert3DSketch True
        n = 0
        For Each item In groups(key)
            pa = nodes(item(0)): pb = nodes(item(1))
            skMgr.CreateLine pa(0), pa(1), pa(2), pb(0), pb(1), pb(2)
            n = n + 1
        Next item
        Set swSketch = skMgr.ActiveSketch
        Set swFeat = Nothing
        On Error Resume Next
        If Not swSketch Is Nothing Then Set swFeat = swSketch     ' Sketch -> Feature cast
        On Error GoTo 0
        skMgr.Insert3DSketch True                                  ' exit this sketch
        If swFeat Is Nothing Then Set swFeat = swModel.Extension.GetLastFeatureAdded
        On Error Resume Next                                       ' a rename clash is reported below
        If Not swFeat Is Nothing Then swFeat.Name = wanted
        On Error GoTo 0
        If swFeat Is Nothing Then
            report = report & wanted & ": " & n & " lines (NOT renamed, rename by hand)" & vbCrLf
        ElseIf swFeat.Name <> wanted Then
            report = report & wanted & ": " & n & " lines (NOT renamed, is " & swFeat.Name & ")" & vbCrLf
        Else
            report = report & wanted & ": " & n & " lines" & vbCrLf
        End If
        total = total + n
    Next key

    skMgr.DisplayWhenAdded = True
    skMgr.AddToDB = False
    swModel.ClearSelection2 True
    swModel.ViewZoomtofit2
    MsgBox total & " tube lines in " & order.Count & " sketches (" & missing & " skipped for missing nodes):" & vbCrLf & vbCrLf & _
           report & vbCrLf & "Next: per group hide the other sketches, box select, Structural Member, rename SM_<group>.", vbInformation
End Sub

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

Private Function InArray(ByVal s As String, ByVal arr As Variant) As Boolean
    Dim k As Long
    For k = 0 To UBound(arr)
        If arr(k) = s Then InArray = True: Exit Function
    Next k
End Function

Private Function FeatureExists(ByVal swModel As SldWorks.ModelDoc2, ByVal nm As String) As Boolean
    Dim f As SldWorks.Feature
    Set f = swModel.FirstFeature
    Do While Not f Is Nothing
        If StrComp(f.Name, nm, vbTextCompare) = 0 Then FeatureExists = True: Exit Function
        Set f = f.GetNextFeature
    Loop
End Function

' Walk up from the .swp folder until params\car_params.txt is found.
Private Function RepoRootFromMacroPath() As String
    Dim p As String
    p = Application.SldWorks.GetCurrentMacroPathName
    If p <> "" Then
        p = Left$(p, InStrRev(p, "\") - 1)
        Do While InStr(p, "\") > 0
            If Dir(p & "\params\car_params.txt") <> "" Then
                RepoRootFromMacroPath = p
                Exit Function
            End If
            p = Left$(p, InStrRev(p, "\") - 1)
        Loop
    End If
    RepoRootFromMacroPath = CurDir$
End Function
