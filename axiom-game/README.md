# AXIOM Synthesis Arena

Open `index.html` in any modern browser. No server, dependencies, or network required.

The game board is an arithmetic AST displayed as a graph, where moves are local or nested rewrites. Every accepted mutation is checked against the original with all 256 (x,y) assignments in the specified 4-bit model. The cost model is illustrative operation weighting, not measured machine cycles. Players can make legal rewrite moves, test a rejected illegal move, undo, invoke a UCT-based Monte Carlo Tree Search (MCTS) turn with random rollouts, and export an evidence JSON record.

This is a bounded learning/demo environment, not a general-purpose synthesis engine. It has no trained policy/value neural network, no compiler integration, and no Lean proofs. The AST graph may be a tree (no shared subexpressions), rather than a physically shared DAG.

Original Node.js prototype from AXIOM v0.1 was not changed.
