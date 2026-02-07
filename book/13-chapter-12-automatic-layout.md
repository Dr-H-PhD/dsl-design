\newpage

# Chapter 12: Automatic Graph Layout

The previous chapters built a complete pipeline: a lexer that tokenises MSD source files, a parser that assembles tokens into structured representations, a semantic analyser that validates meaning, and an output generator that serialises the result as JSON. But the output is not yet complete. An MSD file describes entities, associations, and links — the logical structure of a conceptual data model. It says nothing about where those elements should appear on screen. When a user opens the generated `.merisio` file in Merisio's visual editor, the entities and associations need positions — x and y coordinates that produce a readable, well-organised diagram. This chapter addresses the problem of computing those positions automatically.

## 12.1 The Graph Drawing Problem

A text-based DSL is a compact, declarative way to describe structure. But structure alone is not enough when the output is visual. Consider this MSD fragment:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
}

association Enrol {
    grade: DECIMAL(4,2)
}

link Student (0,N) Enrol
link Course (1,N) Enrol
```

The parser produces two entities, one association, and two links. But where should `Student` appear relative to `Course`? Should `Enrol` sit between them, above them, or off to the side? The MSD source contains no position information whatsoever — and it should not. Positions are a visual concern, not a logical one. Forcing the user to specify coordinates in a text file would defeat the purpose of having a concise, readable language.

This means the tool must compute positions automatically. The requirements for a good automatic layout are:

1. **Proximity**: connected elements should be near each other. `Student` and `Course` are both linked to `Enrol`, so all three should form a visual cluster.
2. **No overlaps**: nodes must not sit on top of one another. Overlapping entities make labels unreadable and the diagram useless.
3. **Visual balance**: the diagram should be roughly centred and evenly distributed, not bunched into one corner.
4. **Determinism**: the same input must always produce the same output. A user who runs the MSD compiler twice on the same file should get identical coordinates both times.

This problem is not unique to MSD. Any DSL that generates visual output faces it:

- **GraphViz** (DOT language) — arranges arbitrary directed and undirected graphs
- **Network topology DSLs** — position routers, switches, and links
- **State machine DSLs** — arrange states and transitions
- **Entity-relationship DSLs** — position entities and relationships (our case)

The field of automatic graph drawing has been studied extensively since the 1960s. Dozens of algorithms exist, each suited to different graph types and aesthetic criteria. For the kind of undirected, moderately sized graphs that MSD produces, **force-directed algorithms** are the natural choice.

---

## 12.2 Force-Directed Algorithms: The Physical Analogy

Force-directed algorithms model a graph as a physical system. The analogy is intuitive: imagine each node as a small charged particle, and each edge as a spring connecting two particles.

- **Charged particles repel each other.** This is the force that prevents overlap and clutter. Every pair of nodes pushes apart, regardless of whether they are connected. Without repulsion, unrelated nodes would drift together and overlap.
- **Springs attract connected nodes.** This is the force that keeps related elements close. An edge between two nodes acts like a spring — it pulls them together if they drift too far apart, and the further apart they are, the stronger the pull.

The algorithm simulates this physical system over many iterations. At each step, it computes the net force on every node (the sum of all repulsive and attractive forces acting on it), then moves each node a small distance in the direction of its net force. Over time, the system reaches **equilibrium** — a state where the forces approximately balance and nodes stop moving. The resulting positions form the layout.

> **Info:** The physical analogy is not just a metaphor — it is the actual mathematical model. The repulsive force follows an inverse-distance law (like electrostatic repulsion), and the attractive force follows a quadratic law (like Hooke's law for springs). The algorithm literally simulates physics.

This family of algorithms includes several well-known variants:

| Algorithm | Year | Key Idea |
|---|---|---|
| Eades | 1984 | Logarithmic springs, inverse-square repulsion |
| Fruchterman-Reingold | 1991 | Simulated annealing with linear cooling |
| Kamada-Kawai | 1989 | Minimise energy based on graph-theoretic distances |
| ForceAtlas2 | 2014 | Adaptive speed, repulsion proportional to degree |

For MSD, we use **Fruchterman-Reingold** — it is simple to implement, produces good results for small to medium graphs, and its simulated annealing approach guarantees convergence.

---

## 12.3 The Fruchterman-Reingold Algorithm

Published by Thomas Fruchterman and Edward Reingold in 1991, this algorithm refines earlier force-directed methods by introducing **simulated annealing** — a technique borrowed from metallurgy where a material is heated and slowly cooled to reach a low-energy state.

The algorithm defines two forces:

**Repulsive force** (applied to all pairs of nodes):

$$F_{rep}(d) = \frac{k^2}{d}$$

where *d* is the distance between two nodes, and *k* is the ideal edge length. Every pair of nodes experiences this repulsion. The closer they are, the stronger the repulsive force.

**Attractive force** (applied only to edges):

$$F_{attr}(d) = \frac{d^2}{k}$$

where *d* is the distance between two connected nodes. The further apart connected nodes are, the stronger the attractive force pulls them back together. The quadratic growth ensures that long edges create strong attraction.

**The ideal edge length** *k* scales with the size of the graph:

$$k = \sqrt{\frac{\text{area}}{n}}$$

where *area* is the drawing area and *n* is the number of nodes. This ensures that the layout adapts to the graph's size — a graph with 5 nodes uses a different scale than one with 50.

**Simulated annealing** controls how far nodes move at each step. The algorithm maintains a **temperature** that starts high and decreases linearly over iterations. At high temperatures, nodes make large movements — this allows them to escape local minima and explore the layout space. As the temperature decreases, movements shrink, allowing the layout to converge to a stable configuration.

- Initial temperature: `t = 2k`
- Cooling per iteration: `cooling = t / iterations`
- At each step: `t = t - cooling`

After enough iterations (typically 50–100), the temperature approaches zero and nodes settle into their final positions.

---

## 12.4 Implementation Walkthrough

MSD's layout engine lives in `layout.py` — a single file of under 200 lines. It implements the Fruchterman-Reingold algorithm with overlap removal and centring as post-processing steps.

### Initial Placement

Before the simulation begins, nodes need starting positions. A common choice is random placement, but this introduces non-determinism. MSD uses **circular placement with a fixed random seed**:

```python
random.seed(42)
radius = k * math.sqrt(n) / 2
for i, node in enumerate(nodes):
    angle = 2 * math.pi * i / n
    node.x = radius * math.cos(angle)
    node.y = radius * math.sin(angle)
```

Arranging nodes in a circle ensures a reasonable starting configuration — no two nodes begin at the same point, and the initial spacing is even. The fixed seed (42) ensures that if any random perturbation is needed later (to break symmetry between coincident nodes), it produces the same perturbation every time.

### Main Loop

The simulation runs for 100 iterations. Each iteration has five steps:

```python
temp = k * 2
cooling = temp / iterations

for _ in range(iterations):
    # 1. Reset displacement arrays
    for i in range(n):
        dx[i] = 0.0
        dy[i] = 0.0

    # 2. Compute repulsive forces (all pairs)
    # 3. Compute attractive forces (edges only)
    # 4. Apply displacements clamped by temperature
    # 5. Cool: reduce temperature
    temp -= cooling
    if temp < 0.1:
        temp = 0.1
```

Let us examine each force computation in detail.

### Repulsive Forces

For every pair of nodes (i, j), the algorithm computes the distance between them and applies an inverse repulsive force:

```python
for i in range(n):
    for j in range(i + 1, n):
        diffx = nodes[i].x - nodes[j].x
        diffy = nodes[i].y - nodes[j].y
        dist = math.sqrt(diffx * diffx + diffy * diffy)
        if dist < 0.01:
            dist = 0.01
            diffx = random.uniform(-0.1, 0.1)
            diffy = random.uniform(-0.1, 0.1)
        force = (k * k) / dist
        fx = (diffx / dist) * force
        fy = (diffy / dist) * force
        dx[i] += fx
        dy[i] += fy
        dx[j] -= fx
        dy[j] -= fy
```

Three details deserve attention:

1. **Minimum distance of 0.01** prevents division by zero. If two nodes happen to occupy the same position, their distance would be zero and the force would be infinite. Clamping to a small positive value avoids this.

2. **Random perturbation** when nodes coincide. If the distance is below 0.01, a small random offset is applied to the direction vector. Without this, two nodes at the exact same position would have a zero direction vector — the force would have magnitude but no direction, and the nodes would never separate. The random perturbation breaks this symmetry.

3. **Newton's third law.** The force on node *i* from node *j* is equal and opposite to the force on node *j* from node *i*. By computing the force once and applying it in opposite directions (`dx[i] += fx`, `dx[j] -= fx`), we halve the number of force computations.

### Attractive Forces

For each edge, the algorithm computes the distance between the two connected nodes and applies a quadratic attractive force:

```python
for ei, ai in edges:
    diffx = nodes[ei].x - nodes[ai].x
    diffy = nodes[ei].y - nodes[ai].y
    dist = math.sqrt(diffx * diffx + diffy * diffy)
    if dist < 0.01:
        dist = 0.01
    force = (dist * dist) / k
    fx = (diffx / dist) * force
    fy = (diffy / dist) * force
    dx[ei] -= fx
    dy[ei] -= fy
    dx[ai] += fx
    dy[ai] += fy
```

Note the sign difference from repulsive forces: attractive forces are subtracted from the source node and added to the target node, pulling them together rather than pushing them apart.

### Displacement Clamping

After computing all forces, each node's accumulated displacement is clamped by the current temperature:

```python
for i in range(n):
    disp = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i])
    if disp > 0:
        scale = min(disp, temp) / disp
        nodes[i].x += dx[i] * scale
        nodes[i].y += dy[i] * scale
```

The clamping formula `scale = min(disp, temp) / disp` ensures that a node never moves further than the current temperature allows in a single step. Early in the simulation, the temperature is high and nodes can make large jumps. Late in the simulation, the temperature is low and nodes make only fine adjustments. This is the essence of simulated annealing — exploration gives way to refinement.

> **Warning:** Without displacement clamping, the algorithm may oscillate indefinitely. A node pushed far by repulsive forces would overshoot, land near another node, get pushed back, and repeat. The temperature acts as a speed limit that gradually brings the system to rest.

---

## 12.5 Post-Processing

The force-directed algorithm treats nodes as dimensionless points. But real nodes have width and height — an entity box might be 140 pixels wide and 100 pixels tall, depending on its number of attributes. Three post-processing steps address this.

### Overlap Removal

After the simulation converges, some nodes may still overlap because the algorithm did not account for their physical size. An iterative overlap removal pass fixes this:

```python
for _ in range(20):
    moved = False
    for i in range(n):
        wi, hi = node_sizes[i]
        for j in range(i + 1, n):
            wj, hj = node_sizes[j]
            ox = (wi + wj) / 2 + 30 - abs(nodes[i].x - nodes[j].x)
            oy = (hi + hj) / 2 + 30 - abs(nodes[i].y - nodes[j].y)
            if ox > 0 and oy > 0:
                if ox < oy:
                    shift = ox / 2 + 1
                    if nodes[i].x < nodes[j].x:
                        nodes[i].x -= shift
                        nodes[j].x += shift
                    else:
                        nodes[i].x += shift
                        nodes[j].x -= shift
                else:
                    shift = oy / 2 + 1
                    if nodes[i].y < nodes[j].y:
                        nodes[i].y -= shift
                        nodes[j].y += shift
                    else:
                        nodes[i].y += shift
                        nodes[j].y -= shift
                moved = True
    if not moved:
        break
```

The overlap test computes the overlap amount on each axis separately, using the node sizes plus a 30-pixel margin. If overlap exists on both axes simultaneously (the bounding boxes intersect), nodes are pushed apart along the axis with the least overlap — this minimises disruption to the layout.

Node sizes are estimated from the model:

- **Entity width**: 140 pixels (fixed)
- **Entity height**: 60 + 18 per attribute
- **Association width**: 120 pixels (fixed)
- **Association height**: 50 + 18 per attribute

The algorithm iterates up to 20 times but stops early if no overlaps remain. For typical MCD models, one or two passes suffice.

### Centring

After overlap removal, the diagram's centroid is shifted to the origin:

```python
cx = sum(nd.x for nd in nodes) / n
cy = sum(nd.y for nd in nodes) / n
for nd in nodes:
    nd.x -= cx
    nd.y -= cy
```

This ensures the diagram appears in the centre of the canvas when opened in the visual editor, rather than being offset to one side.

### Rounding

Finally, all positions are rounded to integers:

```python
for nd in nodes:
    nd.x = round(nd.x)
    nd.y = round(nd.y)
```

Integer positions produce cleaner JSON output (no floating-point noise like `142.00000000003`) and ensure pixel-aligned rendering in the GUI.

---

## 12.6 Determinism Through Fixed Seeds

Determinism is a critical property for any tool in a software development workflow. If the same MSD file produces a different `.merisio` file each time it is compiled, version control systems will show spurious diffs, automated tests cannot assert exact positions, and CI/CD pipelines become unreliable.

MSD's layout achieves determinism through four mechanisms:

1. **Fixed random seed (42).** The `random.seed(42)` call before initial placement ensures that any random values used during the simulation are identical across runs.

2. **Fixed iteration count (100).** The simulation always runs for exactly 100 iterations — it does not terminate based on a convergence threshold, which could vary with floating-point rounding differences across platforms.

3. **Linear cooling.** The temperature decreases by a fixed amount each iteration (`cooling = temp / iterations`), not by a multiplicative factor that could accumulate rounding errors differently.

4. **Integer rounding.** The final rounding step eliminates any residual floating-point differences between runs.

> **Tip:** When building a DSL that generates visual output, always verify determinism in your test suite. A simple test is: run the layout twice on the same input and assert that all coordinates are identical. This catches accidental sources of non-determinism such as dictionary iteration order (in older Python versions), thread-local state, or system clock-seeded random number generators.

The only non-deterministic element in MSD's pipeline is UUID generation (used by the builder to assign unique identifiers to entities, associations, and links). But UUIDs are generated in the builder, not the layout engine, and they do not affect position computation.

---

## 12.7 Complexity Analysis

Understanding the computational complexity of the layout algorithm helps predict its performance on models of different sizes.

| Operation | Complexity |
|---|---|
| Initial placement | O(n) |
| Repulsive forces per iteration | O(n^2^) |
| Attractive forces per iteration | O(e) |
| Total (100 iterations) | O(100 x (n^2^ + e)) |
| Overlap removal | O(20 x n^2^) |

The dominant cost is the repulsive force computation, which considers all pairs of nodes — O(n^2^) per iteration. For typical MCD models with 5 to 20 entities and associations, this means at most a few hundred pair-wise calculations per iteration, completing in well under a millisecond.

For larger models (100+ nodes), the total computation remains well under a second. The quadratic cost only becomes a genuine bottleneck for very large graphs with thousands of nodes. In that regime, the **Barnes-Hut approximation** reduces the repulsive force computation to O(n log n) by grouping distant nodes and treating clusters as single points. However, DSL-scale diagrams rarely exceed a few dozen nodes, making this optimisation unnecessary.

For comparison, GraphViz's `neato` engine uses a similar Fruchterman-Reingold approach for moderate graphs, switching to stress majorisation (Kamada-Kawai variant) for larger ones. ForceAtlas2, used in network visualisation tools like Gephi, handles tens of thousands of nodes through adaptive speed and approximation — far beyond what a database modelling DSL requires.

---

## 12.8 MSD: Auto-Layout for Entities and Associations

With the algorithm understood, let us see how it integrates into MSD's pipeline. The builder calls `auto_layout` after constructing all model objects:

```python
# Auto-layout all elements
all_entities = project.get_all_entities()
all_associations = project.get_all_associations()
all_links = project.get_all_links()

if all_entities or all_associations:
    auto_layout(all_entities, all_associations, layout_links)
```

### Duck Typing via Protocol

The layout engine does not depend on MSD's specific model classes. It works with any objects that have `x`, `y`, and `name` attributes, defined via a structural `Protocol`:

```python
class Positionable(Protocol):
    x: float
    y: float
    name: str
```

This decoupling means the layout engine could be reused with entirely different model classes — any DSL that produces objects with positions and names can use the same layout algorithm.

### Edge Resolution

A subtle challenge arises from the difference between the parser's representation and the builder's representation. The parser produces links with **name-based references** (`entity_name="Student"`, `association_name="Enrol"`). The builder converts these into **UUID-based references** (`entity_id="a7f3..."`, `association_id="b2c8..."`). The layout engine needs to resolve edges regardless of which representation it receives.

The solution is two-fold. The layout engine checks for both attribute names:

```python
ename = getattr(lnk, "entity_name", None) or getattr(lnk, "entity_id", "")
aname = getattr(lnk, "association_name", None) or getattr(lnk, "association_id", "")
```

And the builder creates lightweight proxy objects that translate UUIDs back to names:

```python
class _LayoutLink:
    def __init__(self, entity_name, association_name):
        self.entity_name = entity_name
        self.association_name = association_name

layout_links = []
for lnk in all_links:
    en = id_to_name.get(lnk.entity_id, "")
    an = id_to_name.get(lnk.association_id, "")
    layout_links.append(_LayoutLink(en, an))
```

This proxy pattern keeps the layout engine independent of the model's internal ID scheme while allowing the builder to use it without restructuring its data.

> **Note:** The layout engine indexes nodes by both `name` and `id` (if present) in its `name_to_idx` dictionary. This means it handles name-based links from the parser, UUID-based links from the model, and the proxy objects from the builder — all through the same code path. Duck typing eliminates the need for adapter classes or interface hierarchies.

---

## 12.9 Exercises

**Exercise 12.1** — Implement a simple grid layout as an alternative to force-directed placement. Place entities in rows and columns, with associations positioned between the entities they connect. Compare the results with Fruchterman-Reingold for a model with 6 entities and 5 associations. Under what conditions does the grid layout produce better results? Under what conditions does it produce worse results?

**Exercise 12.2** — The MSD layout uses 100 iterations. Experiment with 10, 50, 100, and 500 iterations on a model with 15 nodes. At what point do additional iterations stop improving the layout? How would you define "improvement" quantitatively — what metric would you use?

**Exercise 12.3** — Modify the overlap removal algorithm to also enforce a minimum edge length of 100 pixels. If two connected nodes are closer than 100 pixels after overlap removal, push them apart to at least that distance. What additional data does the overlap removal step need? How does this interact with the force-directed result?

**Exercise 12.4** — Why is the cooling schedule linear rather than exponential? Implement an exponential cooling schedule where the temperature halves each iteration instead of decreasing by a fixed amount. Run both schedules on the same graph and compare the results. What happens to convergence behaviour? What happens to layout quality?

**Exercise 12.5** — Compute by hand: for 4 nodes arranged in a square with side length 200 and k = 200, what are the repulsive forces between adjacent nodes (distance 200)? Between diagonal nodes (distance 200 x sqrt(2))? If nodes A and B are connected by an edge, what is the attractive force between them? What is the net force on node A from node B?

**Exercise 12.6** — The current algorithm has O(n^2^) complexity for repulsive forces. Research the Barnes-Hut approximation and describe, in pseudocode, how it would reduce this to O(n log n). What data structure does it use? At what graph size would this optimisation become worthwhile for MSD?

**Exercise 12.7** — The layout engine uses duck typing via Python's `Protocol` class. Rewrite the `Positionable` protocol to include optional `width` and `height` attributes. Modify the layout algorithm to use actual node dimensions (when available) during the force-directed simulation itself, not just during post-processing overlap removal. What effect does this have on layout quality?

---
