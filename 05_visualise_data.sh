#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Interactive Input
echo -e "${CYAN}--- Data Visualization ---${NC}"
read -p "Enter experiment directory [default: test_lysozyme]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-test_lysozyme}

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Directory '$PROJECT_DIR' not found."
    exit 1
fi

# Check for GROMACS
if ! command -v gmx &> /dev/null; then
    # Try local install
    if [ -f "$(dirname "$0")/install/bin/GMXRC" ]; then
        source "$(dirname "$0")/install/bin/GMXRC"
    else
        echo "Error: GROMACS not found. Please source GMXRC first."
        exit 1
    fi
fi

cd "$PROJECT_DIR"

# 2. Extract Energy Data
echo -e "${CYAN}--- Extracting Potential Energy ---${NC}"
if [ ! -f "em.edr" ]; then
    echo "Error: 'em.edr' not found in $PROJECT_DIR. Did the simulation run?"
    exit 1
fi

# '10' is usually Potential Energy in GROMACS energy selection
# We pipe "10 0" to select Potential (10) and then exit (0)
echo "10 0" | gmx energy -f em.edr -o energy.xvg

# 3. Clean Data for Gnuplot
# Remove comment lines starting with # or @
grep -v "^[#@]" energy.xvg > clean_energy.dat

# 4. Generate Plot
echo -e "${CYAN}--- Generating Graph (Gnuplot) ---${NC}"
gnuplot <<- EOF
    set terminal pngcairo size 800,600 enhanced font 'Verdana,10'
    set output 'energy_minimization.png'
    # Escape underscores in the title to prevent subscript formatting
    set title "Potential Energy Minimization (${PROJECT_DIR//_/\\\\_})"
    set xlabel "Time (ps)"
    set ylabel "Energy (kJ/mol)"
    set grid
    set style line 1 lc rgb '#0060ad' lt 1 lw 2 pt 7 ps 1.5   # Blue
    plot "clean_energy.dat" using 1:2 with lines ls 1 title 'Potential Energy'
EOF

echo -e "${GREEN}--- Success! ---${NC}"
echo "Graph saved to: $(pwd)/energy_minimization.png"

# Optional: Try to open it if on a desktop environment
if command -v xdg-open &> /dev/null; then
    xdg-open energy_minimization.png
fi

# 5. 3D Visualization (Web Viewer)
echo -e "${CYAN}--- 3D Visualization ---${NC}"
read -p "Generate interactive 3D view (Web)? [y/N]: " LAUNCH_3D
if [[ "$LAUNCH_3D" =~ ^[Yy]$ ]]; then
    if [ -f "em.gro" ]; then
        HTML_FILE="view_structure.html"
        echo "Generating $HTML_FILE..."
        
        # Create HTML with embedded GRO data
        cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Protein Structure: ${PROJECT_DIR}</title>
    <script src="https://unpkg.com/ngl@2.0.0-dev.37/dist/ngl.js"></script>
    <style>
        body { margin: 0; overflow: hidden; background: #1a1a1a; font-family: sans-serif; }
        #viewport { width: 100vw; height: 100vh; }
        #info { position: absolute; top: 10px; left: 10px; color: #eee; z-index: 10; background: rgba(0,0,0,0.7); padding: 15px; border-radius: 8px; pointer-events: none; }
    </style>
</head>
<body>
    <div id="info">
        <h3 style="margin: 0 0 10px 0;">${PROJECT_DIR}</h3>
        <small>Interactive Web Viewer</small><br>
        <small>Left Click: Rotate | Right Click: Pan | Scroll: Zoom</small>
    </div>
    <div id="viewport"></div>
    
    <!-- Embedded Structure Data -->
    <script id="structure-data" type="text/plain">
$(cat em.gro)
    </script>

    <script>
        document.addEventListener("DOMContentLoaded", function () {
            var stage = new NGL.Stage("viewport", {backgroundColor: "#1a1a1a"});
            var data = document.getElementById('structure-data').textContent;
            var blob = new Blob([data], {type: 'text/plain'});
            
            stage.loadFile(blob, {ext: "gro"}).then(function (component) {
                component.addRepresentation("cartoon", {colorScheme: "residueindex"});
                component.addRepresentation("ball+stick", {sele: "ligand"});
                component.addRepresentation("line", {sele: "water", opacity: 0.3});
                component.autoView();
            });
            
            window.addEventListener("resize", function(event){
                stage.handleResize();
            }, false);
        });
    </script>
</body>
</html>
EOF
        echo -e "${GREEN}Success!${NC}"
        echo "Opening $HTML_FILE in default browser..."
        if command -v xdg-open &> /dev/null; then
            xdg-open "$HTML_FILE"
        else
            echo "Open '$HTML_FILE' in your browser manually."
        fi
    else
        echo "Error: em.gro not found."
    fi
fi
