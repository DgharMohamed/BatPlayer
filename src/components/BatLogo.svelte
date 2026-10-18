<script lang="ts">
  import logoUrl from "../assets/batplayer.png";

  let { size = 64 }: { size?: number } = $props();
</script>

<!--
  App emblem: bat mark with a play button (black background of the source PNG
  keyed out). `size` is the rendered width; the height keeps the artwork ratio
  (896x540).
-->
<img
  class="bat-logo"
  src={logoUrl}
  width={size}
  height={Math.round((size * 540) / 896)}
  alt=""
  aria-hidden="true"
  draggable="false"
/>

<style>
  .bat-logo {
    display: block;
    pointer-events: none;
    user-select: none;
  }
</style>
