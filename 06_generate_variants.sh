#!/usr/bin/env bash
set -xe
cd "$(dirname "$0")"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

CANDIDATES_DIR="candidates"
EXPERIMENTS_ROOT="experiments"
SOURCE_PDB="test_lysozyme/1AKI.pdb"

echo -e "${CYAN}--- [06] Variant Generator ---${NC}"

# 1. Check Source
if [ ! -f "$SOURCE_PDB" ]; then
    echo -e "${YELLOW}Source PDB ($SOURCE_PDB) not found. Downloading 1AKI...${NC}"
    mkdir -p test_lysozyme
    wget -q https://files.rcsb.org/download/1AKI.pdb -O "$SOURCE_PDB"
fi

echo "Source: $SOURCE_PDB"

# 2. Select Mode
FORCE_NEW=false
if [[ "$1" == "--new" ]]; then
    FORCE_NEW=true
fi

echo -e "\nSelect Generation Mode:"
echo "1) Random Fragments (Sub-proteins)"
echo "2) Alanine Scanning (Point Mutations to ALA)"
echo "3) Dummy Clones (Exact copies for testing pipeline)"
read -p "Choice [1-3]: " MODE

read -p "How many variants to generate? [5]: " COUNT
COUNT=${COUNT:-5}

# 3. Setup Experiment Directory
TIMESTAMP=$(date +"%Y.%m.%d_%H%M")
PROTEIN_NAME=$(basename "$SOURCE_PDB" .pdb)

case $MODE in
    1) MODE_STR="fragments" ;;
    2) MODE_STR="ala_scan" ;;
    3) MODE_STR="clones" ;;
    *) MODE_STR="custom" ;;
esac

# Group by Protein
PROTEIN_DIR="${EXPERIMENTS_ROOT}/${PROTEIN_NAME}"
mkdir -p "$PROTEIN_DIR"

# Determine Experiment Directory
LATEST_EXP=$(ls -td "${PROTEIN_DIR}"/*_${MODE_STR} 2>/dev/null | head -n 1)

if [ "$FORCE_NEW" = false ] && [ -n "$LATEST_EXP" ]; then
    EXP_DIR="${LATEST_EXP}"
    echo -e "\n${CYAN}Appending to existing experiment: $EXP_DIR${NC}"
else
    EXP_ID="${TIMESTAMP}_${MODE_STR}"
    EXP_DIR="${PROTEIN_DIR}/${EXP_ID}"
    echo -e "\n${CYAN}Initializing New Experiment: $EXP_DIR${NC}"
    mkdir -p "$EXP_DIR"
    cp "$SOURCE_PDB" "$EXP_DIR/source.pdb" # Save reference
fi

CANDIDATES_DIR="${EXP_DIR}/variants"
mkdir -p "$CANDIDATES_DIR"

# Helper: Get sequence length (highest residue number)
# We parse the PDB, look for ATOM records, get residue number (col 23-26), sort numeric, tail 1
MAX_RES=$(grep "^ATOM" "$SOURCE_PDB" | awk '{print $6}' | sort -nu | tail -n 1)
echo "Detected Protein Length: $MAX_RES residues"

generate_fragment() {
    local id=$1
    # Random start and length
    # Min length 20, Max length full
    local len=$((20 + RANDOM % (MAX_RES - 20)))
    local start=$((1 + RANDOM % (MAX_RES - len)))
    local end=$((start + len))
    
    local out_name="variant_${id}_frag_${start}_${end}.pdb"
    
    echo "  > Generating Fragment: Res $start to $end -> $out_name"
    
    # Awk to filter PDB by residue number (column 6 in standard PDB ATOM records)
    # We also keep header lines (HEADER, TITLE, CRYST1) to keep GROMACS happy
    awk -v s="$start" -v e="$end" '
        /^ATOM/ { if ($6 >= s && $6 <= e) print $0 }
        /^HEADER|^TITLE|^CRYST1/ { print $0 }
        /^TER/ { next } 
        /^END/ { next }
    ' "$SOURCE_PDB" > "$CANDIDATES_DIR/$out_name"
    
    # Add TER/END
    echo "TER" >> "$CANDIDATES_DIR/$out_name"
    echo "END" >> "$CANDIDATES_DIR/$out_name"
}

generate_ala_mutant() {
    local id=$1
    # Pick random residue to mutate
    local target=$((1 + RANDOM % MAX_RES))
    
    local out_name="variant_${id}_ala_mut_${target}.pdb"
    
    echo "  > Generating Mutant: Res $target -> ALA -> $out_name"
    
    # Awk script for Alanine mutation
    # 1. Identify target residue rows
    # 2. Change Residue Name (col 18-20) to "ALA"
    # 3. Keep atoms: N, CA, C, O, CB (backbone + beta carbon)
    # 4. Discard other atoms (side chain)
    # 5. Print everything else unchanged
    
    awk -v t="$target" '
        /^ATOM/ && $6 == t {
            # This is the target residue
            atom_name = $3
            
            # Change residue name to ALA (columns 18-20)
            # PDB is fixed width, so we must be careful. 
            # Using substr to reconstruct line is safer than simple sub() which might break columns
            prefix = substr($0, 1, 17)
            suffix = substr($0, 21)
            $0 = prefix "ALA" suffix
            
            # Filter atoms
            if (atom_name == "N" || atom_name == "CA" || atom_name == "C" || atom_name == "O" || atom_name == "CB") {
                print $0
            }
            # Else: skip (delete side chain atoms)
        }
        /^ATOM/ && $6 != t {
            print $0
        }
        !/^ATOM/ {
            print $0
        }
    ' "$SOURCE_PDB" > "$CANDIDATES_DIR/$out_name"
}

generate_dummy() {
    local id=$1
    local out_name="variant_${id}_clone.pdb"
    echo "  > Generating Clone -> $out_name"
    cp "$SOURCE_PDB" "$CANDIDATES_DIR/$out_name"
}

# 3. Execution Loop
echo -e "${CYAN}Generating $COUNT variants...${NC}"

for ((i=1; i<=COUNT; i++)); do
    case $MODE in
        1) generate_fragment $i ;;
        2) generate_ala_mutant $i ;;
        3) generate_dummy $i ;;
        *) echo "Invalid mode"; exit 1 ;;
    esac
done

echo -e "${GREEN}Done! Variants saved to '$CANDIDATES_DIR/'.${NC}"
echo "Run ./07_screen_variants.sh \"$EXP_DIR\" to process them."
