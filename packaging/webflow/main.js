const baseUrl = import.meta.env.BASE_URL.endsWith('/')
  ? import.meta.env.BASE_URL
  : `${import.meta.env.BASE_URL}/`;

document.getElementById('workspace').src = `${baseUrl}brainstory/index.html`;
